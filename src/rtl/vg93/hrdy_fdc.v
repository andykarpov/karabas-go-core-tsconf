//------------------------------------------------------------
// HRDY FDC Top Level
//------------------------------------------------------------
// Beta Disk glue around the VG93 model (vg93_top, github.com/demyanenko-d/FD1793_1818VG93), after its
// epm570/bdi_top.v: the model and the drive glue (fdd_glue) run on clk_bus, the clock of the CPU (28 MHz, 24 MHz
// in the DS80 mode), so the host bus, port #FF, DRQ and INTRQ need no clock domain crossing. CLK of the model is
// 1 MHz in both modes (clk_bus / 28 or / 24), a square wave; TurboFDC (fast step rate and head delays) is the
// VG93_TURBO_STEP build of the model (vg93_config.vh), always on.
// The model takes a written byte as the chip does: the end of /WE arms the register, which loads REG_DAL_IN (one
// latch for all four registers) within the next two microwords (4 us each at CLK 1 MHz). A CPU in turbo writes
// the sector and the command register of TR-DOS faster than that and the second byte overwrote the first: busy
// holds the CPU (WAIT) on an access to a VG93 register for 9..10 us after a write to one, and the model does not
// see the access until then (a held write would load REG_DAL_IN); port #FF does not wait.
// The DOS polls the ports in loops that count their own time out: TR-DOS 5.04T waits for INTRQ / DRQ at #3FD5 in
// 4 x 65536 turns of 51 T (3.8 s at 3.5 MHz), 0.5 s at 28 MHz, less than a stopped drive needs to spin up (NO
// DISC). busy keeps the time between two accesses to the ports (#1F..#7F, #FF) at least that of the 3.5 MHz CPU:
// every T state of the CPU (ena_cpu) between them adds 8 clocks of clk_bus (a T state at 3.5 MHz, 3 MHz in DS80)
// to pace, each clock takes one off, and the next access waits until pace is down to 8; at 3.5 MHz pace stays
// below 8 and the CPU never waits. pace is limited to 1016 clocks (36 us, 127 T at 3.5 MHz).
`default_nettype none

module hrdy_fdc (
	// clocks
	input wire         clk,        // clk_bus, 28 / 24 MHz
	input wire         ds80,       // 1: clk is 24 MHz
	input wire         reset,
	input wire         ena_cpu,    // clock enable of the CPU: a T state

	// cpu signals
	input	wire [15:0] 	a,
	input	wire [7:0]		d,
	input	wire			wr_n,
	input	wire			rd_n,
	input	wire			iorq_n,

	// decoded ports
	input wire          cs_n,
	input wire          csff_n,

	// controller output signals
	output wire         oe_n,
	output wire [7:0]   dout,
	output wire         busy,      // WAIT for the CPU
	output wire         intrq_o,   // INTRQ and DRQ of the model (bits 7, 6 of port #FF)
	output wire         drq_o,

	// physical floppy signals
	output reg			FDC_SIDE1 = 1'b1,
	input	wire			FDC_RDATA,
	input	wire			FDC_WPRT,
	input	wire			FDC_TR00,
	input	wire			FDC_INDEX,
	output reg			FDC_WG = 1'b0,
	output wire			FDC_WR_DATA,
	output reg			FDC_STEP = 1'b0,
	output reg			FDC_DIR = 1'b0,
	output reg			FDC_MOTOR = 1'b0,
	output reg	[1:0]	FDC_DS = 2'b00
);

// CLK of the model: 1 MHz square wave, clk_bus / 28 (28 MHz) or / 24 (24 MHz, DS80)
reg [3:0] cdiv = 4'd0;
reg fdc_clk = 1'b0;
always @(posedge clk) begin
	if (cdiv == (ds80 ? 4'd11 : 4'd13)) begin
		cdiv <= 4'd0;
		fdc_clk <= ~fdc_clk;
	end else
		cdiv <= cdiv + 4'd1;
end

// a VG93 register was written: the model takes the byte within two microwords; count 10 CLK periods
reg vg_wr = 1'b0;
reg [3:0] guard = 4'd0;
reg [1:0] hold_d = 2'b00;
wire fdc_clk_rise = ~fdc_clk & (cdiv == (ds80 ? 4'd11 : 4'd13));
wire port_sel = (~cs_n | ~csff_n) & (~rd_n | ~wr_n);   // not INTA (IORQ with M1, the decoders take any IORQ)
// the time of the 3.5 MHz CPU still owed before the next access to the ports
reg [9:0] pace = 10'd0;
wire pace_wait = (pace > 10'd8);
wire hold = (guard != 4'd0) | pace_wait;
wire vg_cs_n = cs_n | hold;
always @(posedge clk) begin
	hold_d <= {hold_d[0], hold};
	vg_wr <= ~vg_cs_n & ~wr_n;
	if (vg_wr & (vg_cs_n | wr_n))
		guard <= 4'd10;
	else if (fdc_clk_rise && guard != 4'd0)
		guard <= guard - 4'd1;
	if (reset)
		pace <= 10'd0;
	else if (~port_sel & ena_cpu)
		pace <= (pace > 10'd1009) ? 10'd1016 : pace + 10'd7;
	else if (pace != 10'd0)
		pace <= pace - 10'd1;
end
assign busy = port_sel & (hold | hold_d != 2'b00);   // the model sees a held access 2 clocks at least

// BDI system port #FF: bits 1..0 drive, 2 /MR (0 = reset), 3 HLT, 4 side (0 = side 1)
reg [7:0] port_ff_reg = 8'b0;
always @(posedge clk) begin
	if (reset)
		port_ff_reg <= 8'b0;
	else if (~csff_n & ~wr_n & ~iorq_n & ~pace_wait)
		port_ff_reg <= d;
end

// data output
wire drq, intrq;
wire [7:0] dal = (~vg_cs_n & ~wr_n) ? d : 8'bZ;   // DAL of the model: the CPU drives it on a write
assign intrq_o = intrq;
assign drq_o = drq;
assign oe_n = ~((~cs_n | ~csff_n) & ~rd_n);
assign dout = (~cs_n & ~rd_n)  ? dal :
              (~csff_n & ~rd_n) ? {intrq, drq, 6'b111111} :
              8'b11111111;

// vg93
wire motor, wg, wd, step, dirc, rclk, tg43, early, late, rawread_n;
vg93_top vg93_top(
	.SYSCLK (clk),
	.CLK(fdc_clk),
	.MR_n(port_ff_reg[2] & ~reset),

	.CS_n(vg_cs_n),
	.RE_n(rd_n),
	.WE_n(wr_n),
	.A(a[6:5]),
	.DAL(dal),
	.DRQ(drq),
	.INTRQ(intrq),

	.STEP(step),
	.DIRC(dirc),
	.EARLY(early),
	.LATE(late),
	.HLD(motor),
	.TG43(tg43),

	.WG(wg),
	.WD(wd),
	.RCLK(rclk),
	.RAWREAD_n(rawread_n),
	.READY(motor),
	.TR00_n(~FDC_TR00),
	.IP_n(~FDC_INDEX),
	.WPRT_n(~FDC_WPRT),
	.HLT(port_ff_reg[3])
);

// drive: data separator and write precompensation
wire wdata_n;
fdd_glue fdd_glue(
	.clk(clk),
	.ds80(ds80),
	.rdata_n(~FDC_RDATA),
	.rclk(rclk),
	.rawread_n(rawread_n),
	.wd(wd & wg),
	.early(early),
	.late(late),
	.tg43(tg43),
	.wdata_n(wdata_n)
);
assign FDC_WR_DATA = ~wdata_n;

// drive outputs through flip-flops (WD and the decoders are combinational, their glitches would reach the drive)
always @(posedge clk) begin
	FDC_STEP  <= step;
	FDC_DIR   <= dirc;
	FDC_WG    <= wg;
	FDC_MOTOR <= motor;
	FDC_SIDE1 <= ~port_ff_reg[4];
	FDC_DS[0] <= motor & (port_ff_reg[1:0] == 2'b00);
	FDC_DS[1] <= motor & (port_ff_reg[1:0] == 2'b01);
end

endmodule
