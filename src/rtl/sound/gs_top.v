`default_nettype none
/*
  -----------------------------------------------------------------------------
   General Sound for Karabas Go, and the SDRAM of the sound
  -----------------------------------------------------------------------------
  The SDRAM (sdram2p, clk_sys) has two ports, each with one access in every cycle of 8 clk_sys:
  - port 1 (banks 0 / 1): the memory of the GS (ROM page 0 = byte 0..7FFF, loaded by the ROM loader
    at 80000000, and the RAM pages), byte address = the 21-bit address of the GS memory;
  - port 2 (banks 2 / 3): the sample memory of the OPL4 (opl4_kg, 4 MB: the YRW801 ROM 0..1FFFFF,
    loaded from the SD card by an FL item, the sample RAM 200000..3FFFFF).

  The GS Z80 (14 MHz, clk_bus with ce) has a read cache of 512 words, direct mapped (index = address
  bits 9..1, tag = bits 20..10): a hit is read without wait, a miss goes to the SDRAM with WAIT of
  the Z80 (MEM_WAIT of gs.v) until the port is done (about 3 wait states). A write is posted: the
  port takes it at E2 and the Z80 waits only while the port is still busy; a write to a cached
  line updates its byte. The ROM loader writes through the same port while the GS is held.

  Timing of a GS memory cycle, z80-silicon (gs.v SILICON = 1; the clk_bus edges: T1 rise = ce, T1 fall
  = ~ce, ...): MA at T1 rise (the page from the address at once), MREQ / RD at T1 fall, the write data
  with MREQ (a write = MREQ without RD / RFSH; WR itself only at T2 fall); the cache is read with MA at
  T1 fall, its word compared before T2 rise; a miss or a write is sent at T2 rise, WAIT is sampled at
  T2 fall (a hit or a posted write: none), the data at T3 rise (M1) / T3 fall. With T80s (SILICON = 0)
  all of it at the CE edges, the miss / write sent at the second CE.
*/
module gs_top (
    // clocks
    input wire            clk_sys,
    input wire            clk_bus,
    input wire            ce,
    input wire            reset,
    input wire            areset,

    // cpu input signals
    input wire [15:0]      a,
    input wire [7:0]       di,
    input wire            mreq_n,
    input wire            iorq_n,
    input wire            m1_n,
    input wire            rd_n,
    input wire            wr_n,

    // data out to cpu
    output wire           oe,
    output wire [7:0]      do_bus,

	// interface to the MT48LC16M16 chip
	output wire 			 sdram_clk,
	output wire           sdram_ready, // the SDRAM initialised: LD_READY (the ROM / FL bytes have no queue for it)
	inout  wire [15:0]    sdram_dq,
	output wire [12:0]    sdram_a,
	output wire [1:0]     sdram_dqm,
	output wire [1:0]     sdram_ba,
	output wire           sdram_we_n,
	output wire           sdram_ras_n,
	output wire           sdram_cas_n,

    // rom loader interface (clk_bus): the GS ROM at 80000000
   input wire            loader_act,
	input wire [31:0]      loader_a,
	input wire [7:0]       loader_d,
	input wire            loader_wr,

	// the YRW801 ROM of the OPL4 from the FL item (clk_bus): byte offset in the file
	input wire            fl_wr,
	input wire [31:0]     fl_a,
	input wire [7:0]      fl_d,

	// the sample memory of the OPL4 (clk_sys), see opl4_kg
	input wire [21:0]     opl_addr,
	input wire            opl_req,
	input wire            opl_we,
	input wire [7:0]      opl_wdata,
	output wire           opl_ack,
	output wire [15:0]    opl_rdata,

    // sound output
	output wire signed [14:0] out_l,
	output wire signed [14:0] out_r,
	output wire           sample_t    // toggles with each INT of the GS (for audio_lpf)

);

// gs

wire [20:0] gs_mem_addr;
wire  [7:0] gs_mem_dout;
wire  [7:0] gs_mem_din;
wire        gs_mem_rd_n;
wire        gs_mem_wr_n;
wire        gs_mem_wait;

gs gs
(
    .RESET(reset),
    .CLK(clk_bus),
    .CE(ce),
    .CE_N(~ce),          // ce toggles each clk_bus (14 MHz): ~ce is the falling edge of the GS Z80 clock

    .A(a),
    .DI(di),
    .DO(do_bus),
    .OE(oe),
    .WR_n(wr_n),
    .RD_n(rd_n),
    .IORQ_n(iorq_n),
    .M1_n(m1_n),

    .OUT_L(out_l),
    .OUT_R(out_r),
    .SAMPLE_T(sample_t),

    .MA(gs_mem_addr),
    .MDI(gs_mem_din),
    .MDO(gs_mem_dout),
    .MRFSH_n(),
    .MWE_n(gs_mem_wr_n),
    .MRD_n(gs_mem_rd_n),
    .MEM_WAIT(gs_mem_wait)
);

// ------------------------------------------------------------------ port 1: GS (clk_bus)

wire        p1_ack;
wire [15:0] p1_q;

wire gs_rd = ~gs_mem_rd_n;
wire gs_wr = ~gs_mem_wr_n;

// the cache: data in two byte lanes, the tag with its valid bit
reg  [7:0] c_lo [0:511];
reg  [7:0] c_hi [0:511];
reg [11:0] c_tag [0:511];
reg  [7:0] c_lo_q = 8'd0, c_hi_q = 8'd0;
reg [11:0] c_tag_q = 12'd0;
reg [20:0] c_ma_q = 21'd0;            // the address the cache words are of
integer ci;
initial for (ci = 0; ci < 512; ci = ci + 1) begin
	c_lo[ci] = 8'd0; c_hi[ci] = 8'd0; c_tag[ci] = 12'd0;
end

wire [8:0]  c_idx = gs_mem_addr[9:1];
wire        c_fresh = (c_ma_q == gs_mem_addr);
wire        c_match = c_tag_q[11] && c_tag_q[10:0] == gs_mem_addr[20:10];
wire        c_hit = c_fresh && c_match;

reg         p1_req = 1'b0;            // toggle
reg         p1_busy = 1'b0;
reg         p1_gs = 1'b0;             // the access is of the GS (not the loader)
reg         p1_we = 1'b0;
reg  [20:0] p1_a = 21'd0;
reg   [7:0] p1_d = 8'd0;
reg         gs_done = 1'b0;           // the access of this GS cycle is done
reg  [15:0] gs_rdata = 16'd0;

// a loader byte waits here for the port
reg         ld_pend = 1'b0;
reg  [14:0] ld_a = 15'd0;
reg   [7:0] ld_d = 8'd0;

wire p1_done = p1_busy && (p1_ack == p1_req);
// a GS write is posted: it goes to the port at E2 (the Z80 waits only while the port is busy) and
// into the cached line at once
wire gs_wr_go = gs_wr && c_fresh && !gs_done && !p1_busy && !ld_pend;
reg  c_we_lo, c_we_hi, c_we_tag;
reg  [7:0] c_wd_lo, c_wd_hi;
reg [11:0] c_wd_tag;
reg  [8:0] c_wa;

always @(*) begin
	c_we_lo = 1'b0; c_we_hi = 1'b0; c_we_tag = 1'b0;
	c_wd_lo = p1_q[7:0]; c_wd_hi = p1_q[15:8];
	c_wd_tag = {1'b1, p1_a[20:10]};
	c_wa = p1_a[9:1];
	if (p1_done && !p1_we) begin
		// a read fills the line
		c_we_lo = 1'b1; c_we_hi = 1'b1; c_we_tag = 1'b1;
	end else if (p1_done && !p1_gs) begin
		// a loader write takes the line out
		c_we_tag = 1'b1;
		c_wd_tag = 12'd0;
	end else if (gs_wr_go && c_match) begin
		// a GS write to a cached line
		c_wa = gs_mem_addr[9:1];
		c_wd_lo = gs_mem_dout; c_wd_hi = gs_mem_dout;
		c_we_lo = !gs_mem_addr[0];
		c_we_hi = gs_mem_addr[0];
	end
end

always @(posedge clk_bus) begin
	if (c_we_lo) c_lo[c_wa] <= c_wd_lo;
	if (c_we_hi) c_hi[c_wa] <= c_wd_hi;
	if (c_we_tag) c_tag[c_wa] <= c_wd_tag;
	c_lo_q <= c_lo[c_idx];
	c_hi_q <= c_hi[c_idx];
	c_tag_q <= c_tag[c_idx];
	c_ma_q <= gs_mem_addr;
end

always @(posedge clk_bus) begin
	if (loader_wr && loader_a[31]) begin
		ld_pend <= 1'b1;
		ld_a <= loader_a[14:0];
		ld_d <= loader_d;
	end

	if (!gs_rd && !gs_wr)
		gs_done <= 1'b0;

	if (p1_done) begin
		p1_busy <= 1'b0;
		if (p1_gs && !p1_we) begin
			gs_done <= 1'b1;
			gs_rdata <= p1_q;
		end
	end else if (!p1_busy) begin
		if (ld_pend && !(loader_wr && loader_a[31])) begin
			ld_pend <= 1'b0;
			p1_busy <= 1'b1;
			p1_req <= ~p1_req;
			p1_gs <= 1'b0;
			p1_we <= 1'b1;
			p1_a <= {6'd0, ld_a};
			p1_d <= ld_d;
		end else if (gs_wr_go || (!gs_done && c_fresh && gs_rd && !c_match && !ld_pend)) begin
			p1_busy <= 1'b1;
			p1_req <= ~p1_req;
			p1_gs <= 1'b1;
			p1_we <= gs_wr;
			p1_a <= gs_mem_addr;
			p1_d <= gs_mem_dout;
			if (gs_wr) gs_done <= 1'b1;
		end
	end

	if (reset) gs_done <= 1'b0;
end

// WAIT: a read until it hits or is done, a write until the port has taken it
assign gs_mem_wait = !gs_done && ((gs_rd && !c_hit) || (gs_wr && !gs_wr_go));
assign gs_mem_din = gs_done ? (gs_mem_addr[0] ? gs_rdata[15:8] : gs_rdata[7:0])
                            : (gs_mem_addr[0] ? c_hi_q : c_lo_q);

// ------------------------------------------------------------------ port 2: OPL4 (clk_sys)

wire        p2_ack;
wire [15:0] p2_q;

// the FL bytes: ld_wr of clk_bus is high for three clk_sys; a fifo of 4, as a port 2 write waits a
// cycle when port 1 reads and the bytes come every 250 ns (21 clk_sys) at most
reg         fl_wr_d = 1'b0;
reg  [28:0] fl_fifo [0:3];
reg   [2:0] fl_wp = 3'd0, fl_rp = 3'd0;
wire        fl_pend = (fl_wp != fl_rp);
wire [28:0] fl_head = fl_fifo[fl_rp[1:0]];

reg         p2_req = 1'b0;            // toggle
reg         p2_busy = 1'b0;
reg         p2_opl = 1'b0;
reg         p2_we = 1'b0;
reg  [21:0] p2_a = 22'd0;
reg   [7:0] p2_d = 8'd0;

wire p2_done = p2_busy && (p2_ack == p2_req);

always @(posedge clk_sys) begin
	fl_wr_d <= fl_wr;
	if (fl_wr && !fl_wr_d && fl_a[31:21] == 11'd0) begin
		fl_fifo[fl_wp[1:0]] <= {fl_a[20:0], fl_d};
		fl_wp <= fl_wp + 1'd1;
	end

	if (p2_done)
		p2_busy <= 1'b0;
	else if (!p2_busy) begin
		if (fl_pend) begin
			fl_rp <= fl_rp + 1'd1;
			p2_busy <= 1'b1;
			p2_req <= ~p2_req;
			p2_opl <= 1'b0;
			p2_we <= 1'b1;
			p2_a <= {1'b0, fl_head[28:8]};
			p2_d <= fl_head[7:0];
		end else if (opl_req) begin
			p2_busy <= 1'b1;
			p2_req <= ~p2_req;
			p2_opl <= 1'b1;
			p2_we <= opl_we;
			p2_a <= opl_addr;
			p2_d <= opl_wdata;
		end
	end
end

assign opl_ack = p2_done && p2_opl;
assign opl_rdata = p2_q;

// ------------------------------------------------------------------ the SDRAM

sdram2p sdram
(
	.SDRAM_DQ(sdram_dq),
	.SDRAM_A(sdram_a),
	.SDRAM_DQML(sdram_dqm[0]),
	.SDRAM_DQMH(sdram_dqm[1]),
	.SDRAM_BA(sdram_ba),
	.SDRAM_nWE(sdram_we_n),
	.SDRAM_nRAS(sdram_ras_n),
	.SDRAM_nCAS(sdram_cas_n),
	.SDRAM_CLK(sdram_clk),

	.init_n(~areset),
	.clk(clk_sys),
	.ready(sdram_ready),

	.port1_req(p1_req),
	.port1_ack(p1_ack),
	.port1_we(p1_we),
	.port1_a({3'd0, p1_a[20:1]}),
	.port1_ds(p1_we ? {p1_a[0], ~p1_a[0]} : 2'b11),
	.port1_d({p1_d, p1_d}),
	.port1_q(p1_q),

	.port2_req(p2_req),
	.port2_ack(p2_ack),
	.port2_we(p2_we),
	.port2_a({2'd0, p2_a[21:1]}),
	.port2_ds(p2_we ? {p2_a[0], ~p2_a[0]} : 2'b11),
	.port2_d({p2_d, p2_d}),
	.port2_q(p2_q)
);

endmodule
