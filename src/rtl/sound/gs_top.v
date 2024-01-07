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
	inout  wire [15:0]     sdram_dq,
	output wire [12:0]     sdram_a,
	output wire [1:0]      sdram_dqm,
	output wire [1:0]      sdram_ba,
	output wire           sdram_we_n,
	output wire           sdram_ras_n,
	output wire           sdram_cas_n,

    // rom loader interface
   input wire            loader_act,
	input wire [31:0]      loader_a,
	input wire [7:0]       loader_d,
	input wire            loader_wr,

    // sound output
	output wire [15:0] out_l,
	output wire [15:0] out_r

);

// gs

gs #(.INT_DIV(373)) gs 
(
    .RESET(reset),
	.CLK(clk_sys),
	.CE_N(gs_ce_n),
	.CE_P(gs_ce_p),

	.A(a[3]),
	.DI(di),
	.DO(gs_dout),
	.CS_n(~m1_n | iorq_n | ~gs_sel),
	.WR_n(wr_n),
	.RD_n(rd_n),

	.MEM_ADDR(gs_mem_addr),
	.MEM_DI(gs_mem_din),
	.MEM_DO(gs_mem_dout | gs_mem_mask),
	.MEM_RD(gs_mem_rd),
	.MEM_WR(gs_mem_wr),
	.MEM_WAIT(~gs_mem_ready),

	.OUTL(gs_l),
	.OUTR(gs_r)
);

// sdram

sdram sdram
(
    .SDRAM_DQ(sdram_dq),
	.SDRAM_A(sdram_a),
	.SDRAM_DQML(sdram_dqm[0]),
	.SDRAM_DQMH(sdram_dqm[1]),
	.SDRAM_BA(sdram_ba),
	.SDRAM_nCS(),
	.SDRAM_nWE(sdram_we_n),
	.SDRAM_nRAS(sdram_ras_n),
	.SDRAM_nCAS(sdram_cas_n),

	.init_n(areset),
	.clk(clk_sys),
	.clkref(ce_14m),

	// port1 is unused
	.port1_req(1'b0),
	.port1_a(),
	.port1_ds(2'b11),
	.port1_d(),
	.port1_q(),
	.port1_we(1'b0),
	.port1_ack(),

	// port 2 is General Sound CPU
	.port2_req(gs_sdram_req),
	.port2_a(gs_sdram_addr[23:1]),
	.port2_ds(gs_sdram_we ? {gs_sdram_addr[0], ~gs_sdram_addr[0]} : 2'b11),
	.port2_q(gs_sdram_dout),
	.port2_d({gs_sdram_din, gs_sdram_din}),
	.port2_we(gs_sdram_we),
	.port2_ack(gs_sdram_ack)
);

// GS port control
wire [20:0] gs_mem_addr;
wire  [7:0] gs_mem_dout;
wire  [7:0] gs_mem_din;
wire        gs_mem_rd;
wire        gs_mem_wr;
wire        gs_mem_ready;
reg   [7:0] gs_mem_mask;

always @* begin
	gs_mem_mask = 0;
	case(status[21:20])
		0: if(gs_mem_addr[20:19]) gs_mem_mask = 8'hFF; // 512K
		1: if(gs_mem_addr[20])    gs_mem_mask = 8'hFF; // 1024K
		2,3:                      gs_mem_mask = 0;
	endcase
end

reg  [24:0] gs_sdram_addr;
wire [15:0] gs_sdram_dout;
reg   [7:0] gs_sdram_din;
wire        gs_sdram_ack;
reg         gs_sdram_req;
reg         gs_sdram_we;

wire        gs_rom_we = loader_act & loader_wr & loader_a[31];
reg         gs_mem_rd_old;
reg         gs_mem_wr_old;
wire        new_gs_mem_req = (~gs_mem_rd_old & gs_mem_rd) || (~gs_mem_wr_old & gs_mem_wr) || gs_rom_we;

always @(posedge clk_sys) begin

	gs_mem_rd_old <= gs_mem_rd;
	gs_mem_wr_old <= gs_mem_wr;

	if (new_gs_mem_req) begin
		// don't issue a new request if a read followed by a read and the current word address is the same as the previous
		if (gs_sdram_we | gs_rom_we | gs_mem_wr | gs_sdram_addr[20:1] != gs_mem_addr[20:1]) begin
			gs_sdram_req <= ~gs_sdram_req;
			gs_sdram_we <= gs_rom_we | gs_mem_wr;
			gs_sdram_din <= gs_rom_we ? loader_d : gs_mem_din;
		end
		gs_sdram_addr <= gs_rom_we ? loader_a : gs_mem_addr;
	end
end

assign gs_mem_dout = gs_sdram_addr[0] ? gs_sdram_dout[15:8] : gs_sdram_dout[7:0];
assign gs_mem_ready = (gs_sdram_ack == gs_sdram_req) & ~new_gs_mem_req;

///////

reg [21:20] status = 2'b01; // todo: amount of ram for GS
wire  [7:0] gs_dout;
wire [14:0] gs_l, gs_r;
wire gs_sel;
assign gs_sel = (a[7:4] == 4'b1011) & ( a[2:0] == 3'b011) & ~&status[21:20];

reg [3:0] gs_ce_count;
reg gs_no_wait;

always @(posedge clk_sys) begin

	if(reset) begin
		gs_ce_count <= 0;
		gs_no_wait <= 1;
	end else begin
		if (gs_ce_p) gs_no_wait <= 0;
		if (gs_mem_ready) gs_no_wait <= 1;
		if (gs_ce_count == 4'd5) begin
			if (gs_mem_ready | gs_no_wait) gs_ce_count <= 0;
		end else
			gs_ce_count <= gs_ce_count + 1'd1;

	end
end

// 14 MHz (84MHz/6) clock enable for GS card
wire gs_ce_p;
wire gs_ce_n;
assign gs_ce_p = gs_ce_count == 0;
assign gs_ce_n = gs_ce_count == 2;

// 14 MHz ref clock
reg  ce_14m;
reg [5:0] counter = 0;
always @(posedge clk_sys) begin	
	counter <=  counter + 1'd1;
	ce_14m  <= !counter[2:0];
end

// audio out
assign out_l = {1'b0, ~gs_l[14], gs_l[13:0]};
assign out_r = {1'b0, ~gs_r[14], gs_r[13:0]};

assign do_bus = gs_dout;
assign oe = mreq_n & ~iorq_n & ~rd_n & gs_sel; // todo addr[7:0] != 8'h1F and !fdd_sel

endmodule
