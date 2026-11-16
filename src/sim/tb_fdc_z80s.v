`timescale 1ns / 1ps
`default_nettype wire
// tb_fdc_z80s (iverilog): the FDC of the Go with the CPU of tsconf.v: z80-silicon (z80s_t80pa, the enables
// zpos / zneg) running fdc_z80s.asm against hrdy_fdc and the drive of tb_hrdy_fdc (fdc_drive.vh), wired as in
// tsconf.v: WAIT_n = ~busy, ena_cpu = zpos, the ports #1F..#7F / #FF decoded from IORQ without M1, the read
// data of the FDC on its oe_n. PATTERN: 0 14 MHz (zpos / zneg in alternate clocks of 28 MHz), 1 7 MHz,
// 2 3.5 MHz. Checks: Restore (3 steps to TR00), Read Sector (256 bytes = the track, status 0, by INI), Write
// Sector (256 bytes decoded back from WDATA with the CRC, by OUTI), and the poll loop IN A,(#FF) / DJNZ
// (24 T): in turbo busy keeps its turn near that of the 3.5 MHz CPU, at 3.5 MHz the CPU never waits.
// -DCPU_T80PA: the same with T80pa (run_z80s_sim.sh makes its netlist): every number the same as z80-silicon.
// Prints "tb_fdc_z80s: 0 errors".
module tb_fdc_z80s;
parameter integer PATTERN = 0;
localparam real SPEED = 1.0;
localparam real CLK_HALF = 17.778;       // 28.125 MHz
reg clk = 1'b0;
always #(CLK_HALF) clk = ~clk;
integer errors = 0;

// zpos / zneg
reg zpos = 1'b0, zneg = 1'b0, ph = 1'b0;
integer gap = 0;
always @(posedge clk) begin
	zpos <= 1'b0; zneg <= 1'b0;
	if (gap > 0) gap = gap - 1;
	else begin
		if (!ph) zpos <= 1'b1; else zneg <= 1'b1;
		ph = !ph;
		gap = (PATTERN == 0) ? 0 : (PATTERN == 1) ? 1 : 3;
	end
end

reg reset = 1'b1;
wire m1_n, mreq_n, iorq_n, rd_n, wr_n, rfsh_n, halt_n;
wire [15:0] a;
wire [7:0] dout_cpu, fdc_dout;
wire fdc_oe_n, busy;
reg [7:0] ram [0:65535];
integer i;
initial begin
	for (i = 0; i < 65536; i = i + 1) ram[i] = 8'h00;
	$readmemh("fdc_z80s.hex", ram);
end
wire io = !iorq_n && m1_n;
wire cs_n = !(io && a[4:0] == 5'h1F && !a[7]);       // #1F #3F #5F #7F
wire csff_n = !(io && a[7:0] == 8'hFF);
wire [7:0] di = !fdc_oe_n ? fdc_dout : (!mreq_n && !rd_n) ? ram[a] : 8'hFF;
always @(posedge clk) if (!mreq_n && !wr_n && !reset) ram[a] <= dout_cpu;

`ifdef CPU_T80PA
// the same with T80pa as tsconf.v had it (the ghdl netlist of run_z80s_sim.sh), to compare
T80pa cpu (
	.RESET_n(!reset), .CLK(clk), .CEN_p(zpos), .CEN_n(zneg), .WAIT_n(!busy), .INT_n(1'b1), .NMI_n(1'b1),
	.BUSRQ_n(1'b1), .OUT0(1'b1), .R800_mode(1'b0), .DIRSet(1'b0), .DIR(212'd0), .REG(),
	.M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n), .RFSH_n(rfsh_n),
	.HALT_n(halt_n), .BUSAK_n(), .A(a), .DI(di), .DO(dout_cpu)
);
`else
z80s_t80pa cpu (
	.RESET_n(!reset), .CLK(clk), .CEN_p(zpos), .CEN_n(zneg), .WAIT_n(!busy), .INT_n(1'b1), .NMI_n(1'b1),
	.BUSRQ_n(1'b1), .M1_n(m1_n), .MREQ_n(mreq_n), .IORQ_n(iorq_n), .RD_n(rd_n), .WR_n(wr_n), .RFSH_n(rfsh_n),
	.HALT_n(halt_n), .BUSAK_n(), .A(a), .DI(di), .DO(dout_cpu)
);
`endif

// ---- drive ----
reg FDC_RDATA = 1'b0, FDC_INDEX = 1'b0;
wire FDC_TR00;
wire FDC_WPRT = 1'b0;
wire FDC_SIDE1, FDC_WG, FDC_WR_DATA, FDC_STEP, FDC_DIR, FDC_MOTOR;
wire [1:0] FDC_DS;
hrdy_fdc dut (
	.clk(clk), .ds80(1'b0), .reset(reset), .ena_cpu(zpos),
	.a(a), .d(dout_cpu), .wr_n(wr_n), .rd_n(rd_n), .iorq_n(iorq_n),
	.cs_n(cs_n), .csff_n(csff_n), .oe_n(fdc_oe_n), .dout(fdc_dout), .busy(busy),
	.intrq_o(), .drq_o(),
	.FDC_SIDE1(FDC_SIDE1), .FDC_RDATA(FDC_RDATA), .FDC_WPRT(FDC_WPRT), .FDC_TR00(FDC_TR00),
	.FDC_INDEX(FDC_INDEX), .FDC_WG(FDC_WG), .FDC_WR_DATA(FDC_WR_DATA), .FDC_STEP(FDC_STEP),
	.FDC_DIR(FDC_DIR), .FDC_MOTOR(FDC_MOTOR), .FDC_DS(FDC_DS)
);
`include "fdc_drive.vh"

// the marks of the program (OUT (#FE)), the clocks of WAIT in the poll loop
realtime t_mark1 = 0, t_mark2 = 0;
integer poll_waits = 0, in_poll = 0;
always @(posedge clk) begin
	if (io && !wr_n && a[7:0] == 8'hFE) begin
		if (dout_cpu == 8'd1 && !in_poll) begin t_mark1 = $realtime; in_poll = 1; end
		if (dout_cpu == 8'd2 && in_poll == 1) begin t_mark2 = $realtime; in_poll = 2; end
	end
	if (in_poll == 1 && busy) poll_waits = poll_waits + 1;
end

initial begin : test
	real turn;
	reg [15:0] crc;
	for (i = 0; i < 256; i = i + 1) wbuf[i] = 8'hFF - i * 3;
	repeat (40) @(posedge clk);
	reset = 1'b0;
	wait (ram[16'h8007] == 8'hEE || $realtime > 400.0e6);
	repeat (2000) @(posedge clk);
	if (ram[16'h8007] != 8'hEE) begin $display("tb_fdc_z80s: the program did not end"); errors = errors + 1; end
	$display("tb_fdc_z80s: restore: %0d steps, track %0d, status %h", steps, track, ram[16'h8000]);
	if (steps != 3 || track != 0 || ram[16'h8000][0] || !ram[16'h8000][2]) errors = errors + 1;
	turn = (t_mark2 - t_mark1) / 64.0 / (CLK_HALF * 2.0);
	$display("tb_fdc_z80s: poll: %.0f clocks per turn of 24 T (%.0f at 3.5 MHz), %0d clocks of WAIT", turn, 24.0 * 8.0, poll_waits);
	if (PATTERN == 2) begin
		if (poll_waits != 0) errors = errors + 1;
	// busy paces the T states between two accesses to 8 clocks each, the access itself (about 3 T, 2 of
	// them at the turbo rate) is not: 179 clocks at 14 and 7 MHz, the same as T80pa (2026-11-15)
	end else if (turn < 24 * 8 * 0.9 || turn > 24 * 8 * 1.1) errors = errors + 1;
	$display("tb_fdc_z80s: read sector: %0d bytes, status %h", {ram[16'h8004], ram[16'h8003]}, ram[16'h8001]);
	if ({ram[16'h8004], ram[16'h8003]} != 16'd256 || ram[16'h8001] != 8'h00) errors = errors + 1;
	for (i = 0; i < 256; i = i + 1)
		if (ram[16'h9000 + i] !== sector[i]) begin
			if (errors < 10) $display("tb_fdc_z80s: read byte %0d = %h, expected %h", i, ram[16'h9000 + i], sector[i]);
			errors = errors + 1;
		end
	crc = 16'hFFFF;
	crc = crc_byte(crc, 8'hA1); crc = crc_byte(crc, 8'hA1); crc = crc_byte(crc, 8'hA1); crc = crc_byte(crc, 8'hFB);
	for (i = 0; i < 256; i = i + 1) crc = crc_byte(crc, wbuf[i]);
	$display("tb_fdc_z80s: write sector: %0d bytes, status %h, %0d bytes decoded from WDATA",
		{ram[16'h8006], ram[16'h8005]}, ram[16'h8002], wcount);
	if ({ram[16'h8006], ram[16'h8005]} != 16'd256 || ram[16'h8002] != 8'h00 || wcount != 258) errors = errors + 1;
	for (i = 0; i < 256; i = i + 1)
		if (wgot[i] !== wbuf[i]) begin
			if (errors < 10) $display("tb_fdc_z80s: written byte %0d = %h, expected %h", i, wgot[i], wbuf[i]);
			errors = errors + 1;
		end
	if ({wgot[256], wgot[257]} !== crc) begin
		$display("tb_fdc_z80s: written CRC %h%h, expected %h", wgot[256], wgot[257], crc);
		errors = errors + 1;
	end
	$display("tb_fdc_z80s: PATTERN=%0d: done at %.1f ms, %0d errors", PATTERN, $realtime / 1.0e6, errors);
	$finish;
end
endmodule
