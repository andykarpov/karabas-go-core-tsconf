`timescale 1ns / 1ps
/*
 tb_esp_audio (iverilog): the ESP32 audio of the Mini G as in tsconf.v: an I2S source (Philips, 16-bit
 slots, LRCK low = left) at 44.1 kHz of its own clock (+50 ppm against clk_bus, BCK of an unrelated phase)
 with a sine (FREQ Hz, -6 dB) -> i2s_rx -> audio_interp -> audio_lpf (W 18) in the three modes of the OSD
 (MODE 0 the steps, 1 linear, 2 linear + low-pass). The output is taken every OUT_DIV clk_bus (512: the
 PCM5102, 584: the HDMI 48 kHz) into esp_audio.txt for opl4/opl4_lpf.py. Checks that every frame of the
 source arrives (a toggle of sample_t each) and that the right channel carries its own sample.
*/
module tb_esp_audio;
parameter integer FREQ = 5000;
parameter integer MODE = 2;
parameter integer OUT_DIV = 512;
localparam integer NOUT = 2048;

// clk_bus 28.03 MHz
localparam real T = 35.676;
reg clk_bus = 0;
always #(T / 2) clk_bus = ~clk_bus;

// the ESP: BCK = 32 x 44.1 kHz x (1 + 50 ppm)
localparam real FS = 44100.0 * 1.00005;
localparam real TB = 1.0e9 / (FS * 32.0);
reg bck = 0, lrck = 0, sd = 0;
reg [31:0] frame = 32'd0;      // {left, right}
reg [4:0] bit_n = 5'd0;
integer n_src = 0;
reg signed [15:0] smp;
initial begin
	#(TB * 0.37);              // an unrelated phase
	forever #(TB / 2) bck = ~bck;
end
// Philips I2S: LRCK and the data change on the falling BCK, the MSB one BCK after the LRCK edge
always @(negedge bck) begin
	if (bit_n == 5'd31) begin
		smp = $rtoi(16383.0 * $sin(2.0 * 3.14159265358979 * FREQ * n_src / FS));
		frame <= {smp, -smp};      // right = -left
		n_src = n_src + 1;
	end
	bit_n <= bit_n + 1'd1;
	lrck <= (bit_n + 5'd1) >= 5'd16;
	// the bit (bit_n + 1) of the frame starts one BCK late: bit 0 of the frame goes out at bit_n = 0
	sd <= frame[31 - bit_n];
end

wire signed [15:0] esp_l, esp_r;
wire esp_t;
i2s_rx i2s_rx(.clk(clk_bus), .sclk(bck), .rst(1'b0), .lrclk(lrck), .sdata(sd),
	.left_chan(esp_l), .right_chan(esp_r), .sample_t(esp_t));

wire signed [15:0] il, ir;
audio_interp #(.STEP(1648), .STEPS(636)) interp(.clk(clk_bus), .lin(MODE != 0),
	.sample_t(esp_t), .in_l(esp_l), .in_r(esp_r), .out_l(il), .out_r(ir));
wire signed [17:0] fl, fr;
audio_lpf #(.W(18)) lpf(.clk(clk_bus), .en(MODE[1]), .in_l({{2{il[15]}}, il}), .in_r({{2{ir[15]}}, ir}),
	.out_l(fl), .out_r(fr));

// every source frame arrives once; right = -left
integer n_rx = 0, errors = 0;
reg t_d = 0;
always @(posedge clk_bus) begin
	t_d <= esp_t;
	if (t_d != esp_t) begin
		n_rx = n_rx + 1;
		if (esp_r != -esp_l && esp_l != -16'sh8000) begin
			if (errors < 5) $display("tb_esp_audio: left %0d right %0d", esp_l, esp_r);
			errors = errors + 1;
		end
	end
end

integer f, m = 0, c = 0, n_rx0 = 0, n_src0 = 0;
initial f = $fopen("esp_audio.txt", "w");
always @(posedge clk_bus) begin
	c = c + 1;
	if (c == OUT_DIV) begin
		c = 0;
		m = m + 1;
		if (m == 200) begin n_rx0 = n_rx; n_src0 = n_src; end
		if (m > 200) $fdisplay(f, "%0d", $signed(fl[15:0]));
		if (m == 200 + NOUT) begin
			$fclose(f);
			if ((n_rx - n_rx0) - (n_src - n_src0) > 1 || (n_src - n_src0) - (n_rx - n_rx0) > 1) begin
				$display("tb_esp_audio: %0d frames sent, %0d received", n_src - n_src0, n_rx - n_rx0);
				errors = errors + 1;
			end
			$display("tb_esp_audio: %0d errors", errors);
			$finish;
		end
	end
end
endmodule
