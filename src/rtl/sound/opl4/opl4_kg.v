`timescale 1ns / 1ps
// ============================================================================
// ZXM-MoonSound compatible OPL4 (YMF278B: FM + wavetable) for the TS-Conf of
// the Karabas Go / Mini / Mini G. Made from opl4_u16.v of u16_tsconf_gs_v24
// (TS-Conf for ReVerSE-U16): the wavetable part opl4.v (bit exact to ymfm)
// and the FM part opl3_fm (opl3_fpga of Greg Taylor, LGPL-3, checked against
// Nuked-OPL3) are taken as they are.
//
// Ports (low address byte, M1 = 1, not in DOS) as in the ZXM-MoonSound CPLD:
//   #C4 W FM address bank 0 / R status
//   #C5 W FM data   bank 0
//   #C6 W FM address bank 1
//   #C7 W FM data   bank 1
//   #7E W wave address
//   #7F W wave data / R wave data  (#7F in DOS is the VG93 data register)
//
// Clocks: CLK = clk_sys 84 MHz (the wavetable engine, the sample memory),
// CLK28 = clk_bus 28 MHz of the same PLL (the FM part, the Z80 bus).
// Sample memory: 22-bit byte address, MEM_* to the second SDRAM port (gs_top):
//   #000000..#1FFFFF  YRW801 ROM (2 MB), loaded from the SD card (FL item)
//   #200000..#3FFFFF  sample RAM (2 MB)
// ============================================================================
module opl4_kg (
	input  wire        CLK,        // 84 MHz
	input  wire        CLK28,      // 28 MHz
	input  wire        RESET,      // CLK domain

	// Z80 bus (clk_bus)
	input  wire  [7:0] A,
	input  wire  [7:0] DI,
	output wire  [7:0] DO,
	input  wire        IORQ_n,
	input  wire        M1_n,
	input  wire        RD_n,
	input  wire        WR_n,
	input  wire        DOS,
	input  wire        INTERP,     // linear interpolation of the samples (OSD; openMSX does it, ymfm not)
	output wire        SEL,        // port selected (for the read data mux)
	output reg         IRQ,        // FM timer interrupt, active high (not connected in the core)

	// sample memory (CLK domain): MEM_REQ held until MEM_ACK (one clock),
	// MEM_RDATA valid with MEM_ACK: the 16-bit word of the byte address
	output wire [21:0] MEM_ADDR,
	output wire        MEM_REQ,
	output wire        MEM_WE,
	output wire  [7:0] MEM_WDATA,
	input  wire        MEM_ACK,
	input  wire [15:0] MEM_RDATA,

	// audio, signed 16 bit (DO1 + DO2, saturated), CLK domain: taken at the 44.1 kHz tick, held for a
	// sample period; SAMPLE_T toggles with each new sample (for opl4_lpf)
	output reg signed [15:0] OUT_L = 16'sd0,
	output reg signed [15:0] OUT_R = 16'sd0,
	output reg        SAMPLE_T = 1'b0
);

// ---------------------------------------------------------------------------
// port decode
// ---------------------------------------------------------------------------
wire sel_lo = (A[7:1] == 7'b0111111);           // #7E/#7F
wire sel_hi = (A[7:2] == 6'b110001);            // #C4..#C7
assign SEL  = !IORQ_n && M1_n && !DOS && (sel_lo || sel_hi);
wire [2:0] off = sel_lo ? {2'b10, A[0]} : {1'b0, A[1:0]};

// strobes into CLK
reg [2:0] wr_s = 3'd0, rd_s = 3'd0;
reg [2:0] off_r = 3'd0;
reg [7:0] di_r = 8'd0;
reg       wr_p = 1'b0, rd_done_p = 1'b0;
always @(posedge CLK) begin
	wr_s <= {wr_s[1:0], SEL && !WR_n};
	rd_s <= {rd_s[1:0], SEL && !RD_n};
	if (SEL) off_r <= off;
	if (wr_s[0] && !wr_s[1]) di_r <= DI;
	wr_p      <= wr_s[1] && !wr_s[2];
	rd_done_p <= !rd_s[1] && rd_s[2];
end

reg [1:0] INTERP_s = 2'b00;
always @(posedge CLK) INTERP_s <= {INTERP_s[0], INTERP};

// 44.1 kHz sample clock: 84.09 MHz (50 MHz * 37 / 22) * 2252420 / 2^32
reg [31:0] ph = 32'd0;
reg        tick = 1'b0;
always @(posedge CLK) begin
	if (RESET) {tick, ph} <= 33'd0;
	else       {tick, ph} <= {1'b0, ph} + 33'd2252420;
end

// ---------------------------------------------------------------------------
// FM part: opl3_fm in the 28 MHz domain. The FM engine of the YMF278B runs
// at clock/684 = 49.5 kHz against 44.1 kHz output (ratio 192/171). Its
// samples are issued evenly by a phase accumulator (44.1 kHz * 192/171,
// 2529032 / 2^32 of CLK; a sample takes 5.7 us of the 20.2 us), and the
// value at an output tick is interpolated linearly between the last two
// finished FM samples, by the phase since the last FM tick (fm_ph[31:16]):
// the FM timeline delayed by one FM period, sampled at 44.1 kHz. Taking the
// last finished sample instead (as before, and with INTERP = 0) drops one
// FM sample in 8.14 and moves the others by up to a period: broadband noise
// at 10..25 dB under bright FM tones (sim/opl3ref noise.py, build 26111602:
// the "sand" of the MoonBlaster FM songs).
// ---------------------------------------------------------------------------
wire        fm_w;
wire [16:0] fm_wword;
reg  [16:0] fm_word_r = 17'd0;
reg         fm_wtgl = 1'b0, fm_ttgl = 1'b0;
reg  [31:0] fm_ph = 32'd0;
wire [32:0] fm_ph_n = {1'b0, fm_ph} + 33'd2529032;
wire signed [19:0] fm_out_l, fm_out_r;
reg  signed [19:0] fm_ya_l = 20'sd0, fm_ya_r = 20'sd0, fm_yb_l = 20'sd0, fm_yb_r = 20'sd0;
reg  signed [19:0] fm_hold_l = 20'sd0, fm_hold_r = 20'sd0;
// the interpolation, three stages from one snapshot of ya, yb and the phase
reg  signed [19:0] fi_a_l = 20'sd0, fi_a_r = 20'sd0, fi_a2_l = 20'sd0, fi_a2_r = 20'sd0;
reg  signed [20:0] fi_d_l = 21'sd0, fi_d_r = 21'sd0;
reg         [15:0] fi_f = 16'd0;
reg  signed [37:0] fi_p_l = 38'sd0, fi_p_r = 38'sd0;
reg  signed [19:0] fi_v_l = 20'sd0, fi_v_r = 20'sd0;
always @(posedge CLK) begin
	fi_a_l <= fm_ya_l; fi_d_l <= fm_yb_l - fm_ya_l;
	fi_a_r <= fm_ya_r; fi_d_r <= fm_yb_r - fm_ya_r;
	fi_f   <= fm_ph[31:16];
	fi_a2_l <= fi_a_l; fi_p_l <= fi_d_l * $signed({1'b0, fi_f});
	fi_a2_r <= fi_a_r; fi_p_r <= fi_d_r * $signed({1'b0, fi_f});
	fi_v_l <= fi_a2_l + fi_p_l[35:16];   // |d * f| < 2^36: ya + (yb - ya) * f lies between ya and yb
	fi_v_r <= fi_a2_r + fi_p_r[35:16];
end
always @(posedge CLK) begin
	if (RESET) begin
		fm_wtgl <= 1'b0; fm_ttgl <= 1'b0; fm_ph <= 32'd0;
	end else begin
		if (fm_w) begin fm_word_r <= fm_wword; fm_wtgl <= ~fm_wtgl; end
		fm_ph <= fm_ph_n[31:0];
		if (fm_ph_n[32]) begin
			// an FM tick: the sample of the last one is finished (it took 5.7 us of 20.2)
			fm_ttgl <= ~fm_ttgl;
			fm_ya_l <= fm_yb_l; fm_ya_r <= fm_yb_r;
			fm_yb_l <= fm_out_l; fm_yb_r <= fm_out_r;
		end
		if (tick) begin
			fm_hold_l <= INTERP_s[1] ? fi_v_l : fm_yb_l;
			fm_hold_r <= INTERP_s[1] ? fi_v_r : fm_yb_r;
		end
	end
end

opl3_fm fm (
	.clk      (CLK28),
	.reset_a  (RESET),
	.wr_tgl   (fm_wtgl),
	.wr_word  (fm_word_r),
	.tick_tgl (fm_ttgl),
	.out_l    (fm_out_l),
	.out_r    (fm_out_r)
);

wire        core_irq;
always @(posedge CLK) IRQ <= core_irq;
wire signed [15:0] do1_l, do1_r, do2_l, do2_r;

opl4 core (
	.clk        (CLK),
	.reset      (RESET),
	.wr         (wr_p),
	.wr_off     (off_r),
	.wr_data    (di_r),
	.rd_off     (off_r),
	.rd_data    (DO),
	.rd_done    (rd_done_p),
	.sample_tick(tick),
	.interp     (INTERP_s[1]),
	.do1_l      (do1_l),
	.do1_r      (do1_r),
	.do2_l      (do2_l),
	.do2_r      (do2_r),
	.idle       (),
	.busy       (),
	.irq        (core_irq),
	.fm_w       (fm_w),
	.fm_wword   (fm_wword),
	.fm_l       (fm_hold_l),
	.fm_r       (fm_hold_r),
	.mem_addr   (MEM_ADDR),
	.mem_req    (MEM_REQ),
	.mem_we     (MEM_WE),
	.mem_wdata  (MEM_WDATA),
	.mem_ack    (MEM_ACK),
	.mem_rdata  (MEM_RDATA)
);

// ---------------------------------------------------------------------------
// output: DO1 + DO2, saturated
// ---------------------------------------------------------------------------
wire signed [16:0] sum_l = do1_l + do2_l;
wire signed [16:0] sum_r = do1_r + do2_r;
function [15:0] sat16;
	input signed [16:0] v;
	begin
		if (v > 17'sd32767)       sat16 = 16'h7fff;
		else if (v < -17'sd32768) sat16 = 16'h8000;
		else                      sat16 = v[15:0];
	end
endfunction
// the engine writes DO1 / DO2 once a sample period, at the end of its frame (before the next tick)
always @(posedge CLK) if (tick) begin
	OUT_L <= sat16(sum_l);
	OUT_R <= sat16(sum_r);
	SAMPLE_T <= ~SAMPLE_T;
end

endmodule
