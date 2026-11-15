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

// 44.1 kHz sample clock: 84.09 MHz (50 MHz * 37 / 22) * 2252420 / 2^32
reg [31:0] ph = 32'd0;
reg        tick = 1'b0;
always @(posedge CLK) begin
	if (RESET) {tick, ph} <= 33'd0;
	else       {tick, ph} <= {1'b0, ph} + 33'd2252420;
end

// ---------------------------------------------------------------------------
// FM part: opl3_fm in the 28 MHz domain. The FM engine of the YMF278B runs
// at clock/684 = 49.5 kHz against 44.1 kHz output (ratio 192/171), so as in
// ymfm an output period gets one FM sample, and every 171/21-th one a
// second, issued 640 clocks (7.6 us) after the first (a sample takes 5.7 us).
// The FM output used in an output period is the one finished in the
// previous period; it is stable here for at least 9 us around the tick.
// ---------------------------------------------------------------------------
wire        fm_w;
wire [16:0] fm_wword;
reg  [16:0] fm_word_r = 17'd0;
reg         fm_wtgl = 1'b0, fm_ttgl = 1'b0;
reg  [7:0]  fm_acc = 8'd0;
reg  [9:0]  fm_dly = 10'd0;
reg         fm_extra = 1'b0;
wire signed [19:0] fm_out_l, fm_out_r;
reg  signed [19:0] fm_hold_l = 20'sd0, fm_hold_r = 20'sd0;
always @(posedge CLK) begin
	if (RESET) begin
		fm_wtgl <= 1'b0; fm_ttgl <= 1'b0; fm_acc <= 8'd0; fm_extra <= 1'b0;
	end else begin
		if (fm_w) begin fm_word_r <= fm_wword; fm_wtgl <= ~fm_wtgl; end
		if (tick) begin
			fm_ttgl <= ~fm_ttgl;
			fm_hold_l <= fm_out_l;
			fm_hold_r <= fm_out_r;
			if (fm_acc + 8'd21 >= 8'd171) begin
				fm_acc <= fm_acc + 8'd21 - 8'd171;
				fm_extra <= 1'b1;
				fm_dly <= 10'd0;
			end else
				fm_acc <= fm_acc + 8'd21;
		end else if (fm_extra) begin
			fm_dly <= fm_dly + 1'd1;
			if (fm_dly == 10'd639) begin fm_extra <= 1'b0; fm_ttgl <= ~fm_ttgl; end
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
