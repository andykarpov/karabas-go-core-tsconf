`timescale 1ns / 1ps
// ============================================================================
// The sources of a low sample rate into the mixer of clk_bus, interpolated and filtered: the OPL4
// (44.1 kHz) and the GS (a sample per INT of the GS, 14 MHz / 374 = 37.47 kHz).
//
// The mixer and the DACs take the sum of all sources at their own rate (PCM5102 54.7 kHz, HDMI
// 48 kHz) by plain sampling. A 44.1 kHz signal held as steps has images at 44.1 kHz +- f, which
// that sampling folds down into the audio band (44.1 -> 54.7 kHz: 39 kHz -> 15.6 kHz, ...): a
// grain or "sand" over the music. On the ZXM-MoonSound (and the GS) the analog filter after the
// DAC takes them out. Here, the mode of the OSD:
//   0  the steps as they are;
//   1  audio_interp: linear interpolation from the previous sample to the new one over a sample
//      period (one sample of delay, sinc^2: for the OPL4 the images about -36 dB at 39 kHz for a
//      5 kHz tone, -18 dB against the steps; the band -1.5 dB at 10 kHz, -3.4 dB at 15 kHz);
//   2  mode 1 and audio_lpf on the sum of the interpolated sources: two 1-pole stages at 876 kHz
//      (28.03 MHz / 32), k = 1/4: 40 kHz each, -3 dB at 26 kHz together (-1.1 dB at 15 kHz, -5.7 dB
//      at 39 kHz). One low-pass for both sources (it is linear), to save the LUTs of the Mini G.
// ============================================================================

// audio_interp: one source. in_l / in_r held for a sample period (of any clock related to clk);
// sample_t toggles with each new sample. The step = delta * STEP / 2^20, STEP rounded down so the
// ramp never passes the new sample (OPL4: 28.03 MHz / 44.1 kHz = 635.6 clocks a sample, STEP 1648,
// STEPS 636: 99.96 % of the step at the end; GS: 748 clocks, STEP 1401, STEPS 748: 99.97 %); the
// ramp stops after STEPS steps, the next sample starts from the exact value.
module audio_interp #(
	parameter integer STEP = 1648,
	parameter integer STEPS = 636
) (
	input  wire        clk,
	input  wire        lin,               // 1: interpolate, 0: the steps
	input  wire        sample_t,
	input  wire signed [15:0] in_l,
	input  wire signed [15:0] in_r,
	output wire signed [15:0] out_l,
	output wire signed [15:0] out_r
);

// a new sample: the toggle through two flip-flops, the data then stable
reg [2:0] st_s = 3'd0;
always @(posedge clk) st_s <= {st_s[1:0], sample_t};
wire new_s = st_s[2] ^ st_s[1];

localparam integer F = 20;
localparam [11:0] STEP12 = STEP;
localparam [9:0] STEPS10 = STEPS;
reg  signed [15:0] tgt_l = 16'sd0, tgt_r = 16'sd0;     // the new sample
reg  signed [27:0] stp_l = 28'sd0, stp_r = 28'sd0;
reg  signed [F + 15:0] y_l = 0, y_r = 0;              // the ramp, F fraction bits
reg  [9:0] n = 10'd0;
wire signed [16:0] d_l = in_l - tgt_l;
wire signed [16:0] d_r = in_r - tgt_r;

always @(posedge clk) begin
	if (new_s) begin
		tgt_l <= in_l; tgt_r <= in_r;
		y_l <= {tgt_l, {F{1'b0}}};
		y_r <= {tgt_r, {F{1'b0}}};
		stp_l <= d_l * $signed({1'b0, STEP12});
		stp_r <= d_r * $signed({1'b0, STEP12});
		n <= 10'd0;
	end else if (n != STEPS10) begin
		y_l <= y_l + stp_l;
		y_r <= y_r + stp_r;
		n <= n + 1'd1;
	end
end

assign out_l = lin ? y_l[F + 15:F] : tgt_l;
assign out_r = lin ? y_r[F + 15:F] : tgt_r;

endmodule

// audio_lpf: the low-pass of mode 2 on a 17-bit signed sum; en = 0: the input as it is.
module audio_lpf (
	input  wire        clk,
	input  wire        en,
	input  wire signed [16:0] in_l,
	input  wire signed [16:0] in_r,
	output reg  signed [16:0] out_l = 17'sd0,
	output reg  signed [16:0] out_r = 17'sd0
);

// 876 kHz: clk / 32, a divisor of the PCM5102 rate (clk / 512) and the HDMI sample period: a rate
// that is not (clk / 40) leaves the steps of the filter folded into the band (-55 dBFS at 17 kHz)
reg [4:0] div = 5'd0;
always @(posedge clk) div <= div + 1'd1;
wire ce = (div == 5'd0);
localparam integer G = 4;
reg signed [16 + G:0] s1_l = 0, s1_r = 0, s2_l = 0, s2_r = 0;
wire signed [16 + G:0] x_l = {in_l, {G{1'b0}}};
wire signed [16 + G:0] x_r = {in_r, {G{1'b0}}};
wire signed [16 + G:0] e1_l = x_l - s1_l, e1_r = x_r - s1_r;
wire signed [16 + G:0] e2_l = s1_l - s2_l, e2_r = s1_r - s2_r;
always @(posedge clk) if (ce) begin
	s1_l <= s1_l + (e1_l >>> 2);
	s1_r <= s1_r + (e1_r >>> 2);
	s2_l <= s2_l + (e2_l >>> 2);
	s2_r <= s2_r + (e2_r >>> 2);
end

always @(posedge clk) begin
	out_l <= en ? s2_l[16 + G:G] : in_l;
	out_r <= en ? s2_r[16 + G:G] : in_r;
end

endmodule
