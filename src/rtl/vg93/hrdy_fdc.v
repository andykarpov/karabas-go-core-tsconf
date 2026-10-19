//------------------------------------------------------------
// HRDY FDC Top Level
//------------------------------------------------------------
`default_nettype none

module hrdy_fdc (
	// clocks
	input wire        clk,
	input wire        clk_8,
	input wire        reset,
	input wire        turbo_fdc,

	// cpu signals
	input	wire [15:0] a,
	input	wire [7:0]  d,
	input	wire		   m1_n,
	input	wire		   wr_n,
	input	wire		   rd_n,
	input	wire		   iorq_n,

	// decoded ports
	input wire        cs_n,
	input wire        csff_n,

	// controller output signals
	output wire       oe_n,
	output wire [7:0] dout,

	// physical floppy signals
	output wire			FDC_SIDE1,
	input	wire			FDC_RDATA,
	input	wire			FDC_WPRT,
	input	wire			FDC_TR00,
	input	wire			FDC_INDEX,
	output wire			FDC_WG,
	output wire			FDC_WR_DATA,
	output wire			FDC_STEP,
	output wire			FDC_DIR,
	output wire			FDC_MOTOR,
	output wire	[1:0]	FDC_DS
);

localparam VGCOM  = 8'h1F;
localparam VGTRK  = 8'h3F;
localparam VGSEC  = 8'h5F;
localparam VGDAT  = 8'h7F;
localparam VGSYS  = 8'hFF;

// BDI status port #FF
reg [7:0] port_ff_reg;
always @(posedge clk) begin
	if (reset)
		port_ff_reg <= 8'b0;
	else if (~csff_n & ~wr_n & ~iorq_n) 
		port_ff_reg <= d;
end

// CDC for drq, intrq
reg drq_m1, drq_sync;
reg intrq_m1, intrq_sync;
always @(posedge clk) begin
    drq_m1     <= drq;
    drq_sync   <= drq_m1;
    intrq_m1   <= intrq;
    intrq_sync <= intrq_m1;
end

// data output
assign oe_n = ~((~cs_n | ~csff_n) & ~rd_n);
assign dout = (~cs_n & ~rd_n)  ? dal : 
              (~csff_n & ~rd_n) ? {intrq_sync, drq_sync, 6'b111111} : 
              8'b11111111;

// Reset from port #FF clocked by clk8
reg mr_n_sync;
always @(posedge clk_8) begin
    mr_n_sync <= port_ff_reg[2];
end

// vg93
wire [7:0] dal = (~cs_n & ~wr_n) ? d : 8'bZ;
wire drq, intrq, motor, vfoe, wg, wd, rg, rclk, tr43, early, late, rawread_n;
wire fdc_re_n = rd_n | cs_n;
wire fdc_we_n = wr_n | cs_n;
// RAWREAD_n is a pulse of one clk_8 period made of the flip-flops rd_reg: the catcher of vg93_read_path runs
// on clk_8 (it was clocked by the AND of rd_reg, a clock from logic)
vg93_top #(.SYNC_RAWREAD(1)) vg93_top(
	.SYSCLK (clk_8),
	.CLK(fdc_clk),
	.MR_n(mr_n_sync),
	
	.CS_n(cs_n),
	.RE_n(fdc_re_n),
	.WE_n(fdc_we_n),
	.A(a[6:5]),
	.DAL(dal),
	.DRQ(drq),
	.INTRQ(intrq),

	.STEP(FDC_STEP),
	.DIRC(FDC_DIR),
	.EARLY(early),
	.LATE(late),
	.HLD(motor),
	.TG43(tr43),
	
	.WG(wg),
	.WD(wd),
	.RG(rg),
	.RCLK(rclk),
	.RAWREAD_n(rawread_n),
	.READY(motor),
	.TR00_n(~FDC_TR00),
	.IP_n(~FDC_INDEX),
	.WPRT_n(~FDC_WPRT),
	.WF_n_VFOE_n(vfoe),
	.HLT(port_ff_reg[3]),
	.TEST_n(1'b1),
	.DDEN_n(1'b0)
);

assign FDC_SIDE1 = ~port_ff_reg[4];
assign FDC_DS[0] = motor & (port_ff_reg[1:0] == 2'b00);
assign FDC_DS[1] = motor & (port_ff_reg[1:0] == 2'b01);
assign FDC_MOTOR = motor;
assign FDC_WG = wg;

// fdc_clk generator (1 MHz / 2 MHz)
reg [2:0] f;
always @(negedge clk_8) begin
	f <= f + 1'b1;
end

wire f4 = f[0]; // 4 MHz

reg turbo_fdc_sync;
always @(posedge clk_8) begin
	turbo_fdc_sync <= turbo_fdc;
end

// выбор клока для ВГшки (турбирование)
reg f_sel;
always @(posedge reset, posedge clk_8) begin
	if (reset) begin
		f_sel <= 1'b0;
	end else begin
		if (turbo_fdc_sync) begin // логика выбора скорости для турбо
			if (FDC_STEP) begin
				f_sel <= 1'b1; // Шаг головки -> 2 МГц
			end else if (wg || rg) begin
				f_sel <= 1'b0; // Реальное чтение или запись на дискету -> 1 МГц
			end else begin
				f_sel <= 1'b1; // Между секторами и во время ожидания команд -> 2 МГц
			end
		end else begin // обычная скорость
			f_sel <= 1'b0;
		end
	end
end

reg fdc_clk;
always @(posedge clk_8) begin
    if (f_sel) 
        fdc_clk <= f[1]; // 8 MHz / 4 = 2 MHz
    else 
        fdc_clk <= f[2]; // 8 MHz / 8 = 1 MHz
end
	
// RAW Read
reg [1:0] rd_reg;
always @(posedge clk_8) begin
	rd_reg <= {rd_reg[0], FDC_RDATA};
end
assign rawread_n = ~(~rd_reg[1] & rd_reg[0]); // Detect 125 ns pulse

// PLL VG93
reg [4:0] fa;
always @(posedge clk_8) begin
    if (~rawread_n) begin
        if (fa[3:0] < 3)       fa[3:0] <= fa[3:0] + 4;
        else if (fa[3:0] < 5)  fa[3:0] <= fa[3:0] + 3;
        else if (fa[3:0] < 7)  fa[3:0] <= fa[3:0] + 2;
        else if (fa[3:0] == 7) fa[3:0] <= fa[3:0] + 1;
        else if (fa[3:0] > 12) fa[3:0] <= fa[3:0] - 3;
        else if (fa[3:0] > 9)  fa[3:0] <= fa[3:0] - 2;
        else if (fa[3:0] > 8)  fa[3:0] <= fa[3:0] - 1;
        else                   fa <= fa + 1'b1;
    end else begin
        fa <= fa + 1'b1;
    end
end
assign rclk = ~fa[4];

// Write pre-compensation
reg [3:0] wdata;
always @(posedge clk_8) begin
	if (f4) begin
		if (wd) begin
			wdata[0] <= tr43 & late;
			wdata[1] <= !((tr43 & late) | (tr43 & early));
			wdata[2] <= tr43 & early;
			wdata[3] <= 1'b0;
		end else begin
			wdata <= {wdata[2:0], 1'b0};
		end
	end
end
assign FDC_WR_DATA = wdata[3];

endmodule
