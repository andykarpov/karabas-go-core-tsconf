`default_nettype none
/*
  -----------------------------------------------------------------------------
   General Sound for Karabas Go
  -----------------------------------------------------------------------------
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
	inout  wire [15:0]    sdram_dq,
	output wire [12:0]    sdram_a,
	output wire [1:0]     sdram_dqm,
	output wire [1:0]     sdram_ba,
	output wire           sdram_we_n,
	output wire           sdram_ras_n,
	output wire           sdram_cas_n,

    // rom loader interface
   input wire            loader_act,
	input wire [31:0]      loader_a,
	input wire [7:0]       loader_d,
	input wire            loader_wr,

    // sound output
	output wire [14:0] out_l,
	output wire [14:0] out_r

);

// gs

wire [20:0] gs_mem_addr;
wire  [7:0] gs_mem_dout;
wire  [7:0] gs_mem_din;
wire        gs_mem_rd_n;
wire        gs_mem_wr_n;

wire [14:0] gs_l, gs_r;
wire [13:0] out_a, out_b, out_c, out_d;

gs gs 
(
    .RESET(reset),
    .CLK(clk_bus),
    .CE(ce), 
    
    .A(a),
    .DI(di),
    .DO(do_bus),
    .OE(oe),
    .WR_n(wr_n),
    .RD_n(rd_n),
    .IORQ_n(iorq_n),
    .M1_n(m1_n),

    .OUTA(out_a),
    .OUTB(out_b),
    .OUTC(out_c),
    .OUTD(out_d),

    .MA(gs_mem_addr),
    .MDI(gs_mem_din),
    .MDO(gs_mem_dout),
    .MRFSH_n(sdr_rfsh_n),
    .MWE_n(gs_mem_wr_n),
    .MRD_n(gs_mem_rd_n)
);

// sdram, loder

wire [24:0] sdr_a;
wire [7:0] sdr_di;
wire [7:0] sdr_do;
wire sdr_wr, sdr_rd, sdr_rfsh_n;
wire [7:0] gs_rom_dout;

assign sdr_wr = (loader_act ?  loader_wr & loader_a[31] : ~gs_mem_wr_n);
assign sdr_rd = (loader_act ? 1'b0 : ~gs_mem_rd_n);
assign sdr_a = (loader_act & loader_a[31]) ? {10'b0000000000, loader_a[14:0]} : {4'b0000, gs_mem_addr};
assign sdr_di = (loader_act & loader_a[31]) ? loader_d : gs_mem_dout;
assign gs_mem_din = sdr_do;

sdram sdram
(
    .CLK(clk_sys),

    .A(sdr_a),
    .DI(sdr_di),
    .DO(sdr_do),
    .WR(sdr_wr),
    .RD(sdr_rd),
    .RFSH(~loader_act & ~sdr_rfsh_n),
    .RFSHREQ(),
    .IDLE(),
    
    .CK(sdram_clk),
    .RAS_n(sdram_ras_n),
    .CAS_n(sdram_cas_n),
    .WE_n(sdram_we_n),
    .DQML(sdram_dqm[0]),
    .DQMH(sdram_dqm[1]),
    .BA(sdram_ba),
    .MA(sdram_a),
    .DQ(sdram_dq)
    
);

assign gs_l = out_a + out_b;
assign gs_r = out_c + out_d;

assign out_l = gs_l;
assign out_r = gs_r;

endmodule
