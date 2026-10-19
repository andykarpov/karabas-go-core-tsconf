`timescale 1ns / 1ps

// hdmi_top (rtl/hdmi/hdmi_top.v), ISim with the unisim models of the DCMs and clock buffers:
// the video of the core (28 MHz), then of the FT812 at 40 and at 72 MHz (hdmi_pll measures the
// clock and programs DCM_CLKGEN), checked where it enters hdmi_tx (host_vga_*):
// - every active pixel of a frame in order: the pixel value is its index in the frame (24 bits,
//   so a bit taken from the wrong place shows), a frame has all of them, each line its hsync;
// - the audio samples: audio_l counts the clocks of clk_ref, audio_r is its complement, so a
//   sample must be r = ~l (both halves of one sample) and the step from the sample before must
//   be CLKRATE / SAMPLERATE clocks; the number of samples per phase gives the rate.
// Ends with "tb_hdmi_top: N errors".

module tb_hdmi_top;

parameter SAMPLERATE = 48000;
localparam integer SAMPLE_DIV = 28000000 / SAMPLERATE;

// frame of the generators (small, so a phase has several frames)
localparam H_TOTAL = 320, H_ACTIVE = 192, HS_START = 220, HS_LEN = 24;
localparam V_TOTAL = 24, V_ACTIVE = 16, VS_START = 18, VS_LEN = 2;
localparam ACTIVE_PIX = H_ACTIVE * V_ACTIVE;

reg clk_ref = 1'b0, clk_8 = 1'b0, ft_clk = 1'b0;
always #17.857 clk_ref = ~clk_ref;   // 28 MHz
always #62.5 clk_8 = ~clk_8;         // 8 MHz
real ft_half = 12.5;
always #(ft_half) ft_clk = ~ft_clk;

reg reset = 1'b1;
reg ft_sel = 1'b0;
wire clk = ft_sel ? ft_clk : clk_ref; // the BUFGMUX of the tops

// ---------------- video generators ----------------

// the core: outputs change with the falling clock (hdmi_top takes them at the rising one)
reg [9:0] vh = 10'd0, vv = 10'd0;
reg [23:0] vpix = 24'd0;
reg [23:0] vga_rgb = 24'd0;
reg vga_hs = 1'b0, vga_vs = 1'b0, vga_de = 1'b0;
always @(negedge clk_ref) begin
	vh <= (vh == H_TOTAL - 1) ? 10'd0 : vh + 10'd1;
	if (vh == H_TOTAL - 1) vv <= (vv == V_TOTAL - 1) ? 10'd0 : vv + 10'd1;
	vga_de <= (vh < H_ACTIVE) && (vv < V_ACTIVE);
	vga_hs <= (vh >= HS_START) && (vh < HS_START + HS_LEN);
	vga_vs <= (vv >= VS_START) && (vv < VS_START + VS_LEN);
	if ((vh < H_ACTIVE) && (vv < V_ACTIVE)) begin
		vga_rgb <= vpix;
		vpix <= vpix + 24'd1;
	end
	else
		vga_rgb <= 24'hA5A5A5;
	if (vh == H_TOTAL - 1 && vv == V_TOTAL - 1) vpix <= 24'd0;
end

// the FT812: outputs change with the rising FT_CLK (hdmi_top takes them at the falling one)
reg [9:0] fh = 10'd0, fv = 10'd0;
reg [23:0] fpix = 24'd0;
reg [23:0] ft_rgb = 24'd0;
reg ft_hs = 1'b0, ft_vs = 1'b0, ft_de = 1'b0;
always @(posedge ft_clk) begin
	fh <= (fh == H_TOTAL - 1) ? 10'd0 : fh + 10'd1;
	if (fh == H_TOTAL - 1) fv <= (fv == V_TOTAL - 1) ? 10'd0 : fv + 10'd1;
	ft_de <= (fh < H_ACTIVE) && (fv < V_ACTIVE);
	ft_hs <= (fh >= HS_START) && (fh < HS_START + HS_LEN);
	ft_vs <= (fv >= VS_START) && (fv < VS_START + VS_LEN);
	if ((fh < H_ACTIVE) && (fv < V_ACTIVE)) begin
		ft_rgb <= fpix;
		fpix <= fpix + 24'd1;
	end
	else
		ft_rgb <= 24'h5A5A5A;
	if (fh == H_TOTAL - 1 && fv == V_TOTAL - 1) fpix <= 24'd0;
end

// audio: changes every clock of clk_ref
reg [15:0] audio_l = 16'd0;
always @(negedge clk_ref) audio_l <= audio_l + 16'd1;
wire [15:0] audio_r = ~audio_l;

// ---------------- DUT ----------------

wire [3:0] tmds_p, tmds_n;
wire [7:0] freq;
hdmi_top #(.SAMPLERATE(SAMPLERATE)) dut(
	.clk(clk), .clk_ref(clk_ref), .clk_8(clk_8), .reset(reset),
	.vga_rgb(vga_rgb), .vga_hs(vga_hs), .vga_vs(vga_vs), .vga_de(vga_de),
	.ft_rgb(ft_rgb), .ft_hs(ft_hs), .ft_vs(ft_vs), .ft_de(ft_de),
	.ft_sel(ft_sel), .audio_en(1'b1), .audio_l(audio_l), .audio_r(audio_r),
	.tmds_p(tmds_p), .tmds_n(tmds_n), .freq(freq)
);

// ---------------- checks ----------------

integer errors = 0;
task automatic fail;
	input [8*48-1:0] what;
	input [31:0] got;
	input [31:0] exp;
	begin
		errors = errors + 1;
		if (errors <= 20)
			$display("%t ERROR: %0s: got %h, expected %h", $time, what, got, exp);
	end
endtask

reg checking = 1'b0;       // set by the phases once the clocks are settled
wire pclk = dut.p_clk_int;
wire [23:0] t_rgb = {dut.host_vga_r, dut.host_vga_g, dut.host_vga_b};
wire t_de = ~dut.host_vga_blank;
wire t_hs = dut.host_vga_hs;
wire t_vs = dut.host_vga_vs;

reg in_frame = 1'b0;       // a frame start (vsync) seen since checking began
reg [23:0] exp_pix = 24'd0;
integer lines = 0, frames = 0;
reg prev_hs = 1'b0, prev_vs = 1'b0;
always @(posedge pclk) begin
	prev_hs <= t_hs;
	prev_vs <= t_vs;
	if (!checking) begin
		in_frame <= 1'b0;
	end
	else begin
		if (t_vs && !prev_vs) begin // the end of the active lines and the start of the next frame
			if (in_frame) begin
				if (exp_pix != ACTIVE_PIX) fail("pixels in a frame", exp_pix, ACTIVE_PIX);
				if (lines != V_TOTAL) fail("lines in a frame", lines, V_TOTAL);
				frames = frames + 1;
			end
			in_frame <= 1'b1;
			exp_pix <= 24'd0;
			lines = 0;
		end
		else begin
			if (t_hs && !prev_hs) lines = lines + 1;
			if (in_frame && t_de) begin
				if (t_rgb != exp_pix) fail("pixel", t_rgb, exp_pix);
				exp_pix <= exp_pix + 24'd1;
			end
		end
	end
end

integer samples = 0;
reg have_prev = 1'b0;
reg [15:0] prev_l = 16'd0;
always @(posedge pclk) begin
	if (!checking) begin
		have_prev <= 1'b0;
	end
	else if (dut.audio_clk) begin
		samples = samples + 1;
		if (dut.hdmi_audio_r[23:8] != ~dut.hdmi_audio_l[23:8])
			fail("sample halves (r = ~l)", {dut.hdmi_audio_l[23:8], dut.hdmi_audio_r[23:8]}, {dut.hdmi_audio_l[23:8], ~dut.hdmi_audio_l[23:8]});
		if (dut.hdmi_audio_l[7:0] != 8'd0 || dut.hdmi_audio_r[7:0] != 8'd0)
			fail("sample low bits", {dut.hdmi_audio_l[7:0], dut.hdmi_audio_r[7:0]}, 0);
		if (have_prev && (dut.hdmi_audio_l[23:8] - prev_l) != SAMPLE_DIV[15:0])
			fail("sample step", dut.hdmi_audio_l[23:8] - prev_l, SAMPLE_DIV);
		prev_l <= dut.hdmi_audio_l[23:8];
		have_prev <= 1'b1;
	end
end

// ---------------- phases ----------------

task automatic phase;
	input [8*16-1:0] name;
	input [7:0] exp_freq;
	input integer settle_us;
	input integer check_us;
	integer f0, s0, exp_samples;
	begin
		#(settle_us * 1000);
		@(negedge clk_ref);
		if (dut.hdmi_pll.hdmi_freq !== exp_freq) fail("detected frequency", dut.hdmi_pll.hdmi_freq, exp_freq);
		if (dut.lockedx5 !== 1'b1) fail("DCM locked", dut.lockedx5, 1);
		f0 = frames; s0 = samples;
		checking = 1'b1;
		#(check_us * 1000);
		@(negedge clk_ref);
		checking = 1'b0;
		exp_samples = check_us * (SAMPLERATE / 1000) / 1000;
		$display("%t %0s: %0d MHz, %0d frames, %0d samples (expected %0d)", $time, name, dut.hdmi_pll.hdmi_freq,
			frames - f0, samples - s0, exp_samples);
		if (frames - f0 < 3) fail("frames checked", frames - f0, 3);
		if (samples - s0 < exp_samples - 2 || samples - s0 > exp_samples + 2) fail("samples", samples - s0, exp_samples);
	end
endtask

initial begin
	#1000;
	@(negedge clk_ref) reset = 1'b0;
	phase("core 28 MHz", 8'd28, 300, 1500);

	ft_half = 12.5; // 40 MHz
	@(negedge clk_ref) ft_sel = 1'b1;
	phase("FT 40 MHz", 8'd40, 3500, 1500);

	ft_half = 6.944; // 72 MHz
	phase("FT 72 MHz", 8'd72, 3500, 1500);

	@(negedge clk_ref) ft_sel = 1'b0;
	phase("core 28 MHz", 8'd28, 1000, 1000);

	$display("tb_hdmi_top: %0d errors", errors);
	$finish;
end

endmodule
