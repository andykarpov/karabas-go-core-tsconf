`timescale 1ns / 1ps
/*
 tb_opl4_lpf (iverilog): audio_interp + audio_lpf (audio_lpf.v) in the three modes of the OSD with a sine (FREQ Hz, -6 dB) at the rate of a
 clk_sys tick (INC: 44.1 kHz of opl4_kg, or the 37.47 kHz of the GS INT with GS = 1); the output
 taken at the rate of the PCM5102 of the tops (clk_bus / 512 = 54.7 kHz) into opl4_lpf.txt for
 opl4_lpf.py (the level of the tone and of everything else).
*/
module tb_opl4_lpf;
parameter integer FREQ = 5000;
parameter integer MODE = 2;
parameter integer GS = 0;
localparam [32:0] INC = GS ? 33'd1913978 : 33'd2252420;
localparam real FS_IN = GS ? 28030303.0 / 748.0 : 44100.0;
localparam real T = 11.892;
reg clk = 0;
always #(T / 2) clk = ~clk;
reg clk_bus = 0;
integer div = 0;
always @(posedge clk) begin
	div = (div + 1) % 3;
	if (div == 0) clk_bus <= 1'b1;
	if (div == 1) clk_bus <= 1'b0;
end

// the tick of the sample rate (opl4_kg: 44.1 kHz)
reg [31:0] ph = 0;
reg tick = 0;
always @(posedge clk) {tick, ph} <= {1'b0, ph} + INC;
reg st = 0;
reg signed [15:0] in_l = 0;
integer n = 0;
always @(posedge clk) if (tick) begin
	in_l <= $rtoi(16383.0 * $sin(2.0 * 3.14159265358979 * FREQ * n / FS_IN));
	n = n + 1;
	st <= ~st;
end

wire signed [15:0] il, ir;
wire signed [16:0] fl, fr;
audio_interp #(.STEP(GS ? 1401 : 1648), .STEPS(GS ? 748 : 636)) interp(.clk(clk_bus), .lin(MODE != 0),
	.sample_t(st), .in_l(in_l), .in_r(in_l), .out_l(il), .out_r(ir));
audio_lpf lpf(.clk(clk_bus), .en(MODE[1]), .in_l({il[15], il}), .in_r({ir[15], ir}), .out_l(fl), .out_r(fr));
wire signed [15:0] out_l = fl[15:0];

integer f, m = 0;
reg [8:0] c = 0;
initial f = $fopen("opl4_lpf.txt", "w");
always @(posedge clk_bus) begin
	c <= c + 1'd1;
	if (c == 0) begin
		m = m + 1;
		if (m > 200) $fdisplay(f, "%0d", out_l);
		if (m == 200 + 8192) begin $fclose(f); $finish; end
	end
end
endmodule
