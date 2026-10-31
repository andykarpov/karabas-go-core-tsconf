// hrdy_fdc (the VG93 model, fdd_glue, the Beta Disk port #FF) on clk_bus with a model of a drive: a track of one
// MFM sector (track 0, side 0, sector 1, 256 bytes) played in a loop at 250 kbit/s with the speed SPEED and a
// jitter of the flux transitions, an index pulse per revolution, STEP / DIRC moving the head, TR00.
// The CPU side (the port decoders are in profi.vhd / zports.v: cs_n / csff_n driven here):
//   Restore (rate 6 ms): the head steps from track 3 to 0, the steps 3 ms apart (TurboFDC, VG93_TURBO_STEP);
//   Read Sector: 256 bytes by DRQ, equal to the track, status 0;
//   Write Sector: 256 bytes by DRQ, status 0; the WDATA pulses decoded back (sync, FB, data, CRC) here.
// The CPU writes the registers back to back (a CPU in turbo): busy (WAIT) must keep the model from losing them.
// DS80 = 1: clk_bus 24.107 MHz instead of 28.125 MHz (the CLK divider and the separator follow ds80).
// TURBO = 1: ena_cpu every clock (x8), 0: every 8th clock (3.5 MHz). The CPU idles GAP clocks between the accesses
// of the transfer loops. Poll: the INTRQ / DRQ loop of TR-DOS (#3FD5, 51 T, one read of #FF) as 64 reads of #FF
// with 47 T between them: in turbo busy must keep the period that of the 3.5 MHz CPU (the time out of the loop),
// at 3.5 MHz the CPU must never wait.
`timescale 1ns / 1ps
`default_nettype wire

module tb_hrdy_fdc;

parameter DS80 = 0;
parameter real SPEED = 1.0;           // drive speed factor: > 1 the disk turns slower (longer cells)
parameter TURBO = 1;
parameter GAP = 20;

real CLK_HALF = DS80 ? 20.741 : 17.778;   // 24.107 / 28.125 MHz
reg clk = 1'b0;
always #(CLK_HALF) clk = ~clk;

integer errors = 0;

// ena_cpu: a T state of the CPU
reg [2:0] ecnt = 3'd0;
always @(posedge clk) ecnt <= ecnt + 3'd1;
wire ena_cpu = TURBO ? 1'b1 : (ecnt == 3'd7);
integer waits = 0;                       // clocks of WAIT seen by the CPU

// ---- CPU bus ----
reg reset = 1'b1;
reg [15:0] a = 16'hFFFF;
reg [7:0] d = 8'hFF;
reg wr_n = 1'b1, rd_n = 1'b1, iorq_n = 1'b1;
reg cs_n = 1'b1, csff_n = 1'b1;
wire oe_n, busy;
wire [7:0] dout;

// ---- drive ----
reg FDC_RDATA = 1'b0, FDC_INDEX = 1'b0;
wire FDC_TR00;
wire FDC_WPRT = 1'b0;
wire FDC_SIDE1, FDC_WG, FDC_WR_DATA, FDC_STEP, FDC_DIR, FDC_MOTOR;
wire [1:0] FDC_DS;

hrdy_fdc dut (
	.clk(clk), .ds80(DS80 != 0), .reset(reset), .ena_cpu(ena_cpu),
	.a(a), .d(d), .wr_n(wr_n), .rd_n(rd_n), .iorq_n(iorq_n),
	.cs_n(cs_n), .csff_n(csff_n), .oe_n(oe_n), .dout(dout), .busy(busy),
	.FDC_SIDE1(FDC_SIDE1), .FDC_RDATA(FDC_RDATA), .FDC_WPRT(FDC_WPRT), .FDC_TR00(FDC_TR00),
	.FDC_INDEX(FDC_INDEX), .FDC_WG(FDC_WG), .FDC_WR_DATA(FDC_WR_DATA), .FDC_STEP(FDC_STEP),
	.FDC_DIR(FDC_DIR), .FDC_MOTOR(FDC_MOTOR), .FDC_DS(FDC_DS)
);

// head position, the times of the steps
integer track = 3, steps = 0;
realtime step_t0 = 0, step_t1 = 0;
assign FDC_TR00 = (track == 0);
always @(posedge FDC_STEP) begin
	track = FDC_DIR ? track + 1 : (track > 0 ? track - 1 : 0);
	steps = steps + 1;
	step_t0 = step_t1;
	step_t1 = $realtime;
end

// ---- the track: MFM channel words ----
function [15:0] crc_byte(input [15:0] crc, input [7:0] b);
	integer i;
	begin
		crc_byte = crc ^ {b, 8'h00};
		for (i = 0; i < 8; i = i + 1)
			crc_byte = crc_byte[15] ? {crc_byte[14:0], 1'b0} ^ 16'h1021 : {crc_byte[14:0], 1'b0};
	end
endfunction

reg [7:0] sector [0:255];
reg [7:0] tbytes [0:1023];
reg       tsync  [0:1023];
reg [15:0] chan  [0:1023];
integer tlen = 0;

task put(input [7:0] b, input s);
	begin tbytes[tlen] = b; tsync[tlen] = s; tlen = tlen + 1; end
endtask

task build_track;
	integer i;
	reg [15:0] crc;
	reg prev;
	reg [7:0] b;
	begin
		for (i = 0; i < 256; i = i + 1) sector[i] = (i * 7 + 8'h35) ^ (i >> 3);
		for (i = 0; i < 40; i = i + 1) put(8'h4E, 0);
		for (i = 0; i < 12; i = i + 1) put(8'h00, 0);
		crc = 16'hFFFF;
		for (i = 0; i < 3; i = i + 1) begin put(8'hA1, 1); crc = crc_byte(crc, 8'hA1); end
		put(8'hFE, 0); crc = crc_byte(crc, 8'hFE);
		put(8'h00, 0); crc = crc_byte(crc, 8'h00);   // C
		put(8'h00, 0); crc = crc_byte(crc, 8'h00);   // H
		put(8'h01, 0); crc = crc_byte(crc, 8'h01);   // R
		put(8'h01, 0); crc = crc_byte(crc, 8'h01);   // N: 256
		put(crc[15:8], 0); put(crc[7:0], 0);
		for (i = 0; i < 22; i = i + 1) put(8'h4E, 0);
		for (i = 0; i < 12; i = i + 1) put(8'h00, 0);
		crc = 16'hFFFF;
		for (i = 0; i < 3; i = i + 1) begin put(8'hA1, 1); crc = crc_byte(crc, 8'hA1); end
		put(8'hFB, 0); crc = crc_byte(crc, 8'hFB);
		for (i = 0; i < 256; i = i + 1) begin put(sector[i], 0); crc = crc_byte(crc, sector[i]); end
		put(crc[15:8], 0); put(crc[7:0], 0);
		for (i = 0; i < 60; i = i + 1) put(8'h4E, 0);
		// MFM: a clock bit between two data zeros; the sync A1 with the missing clock: 4489
		prev = 1'b0;
		for (i = 0; i < tlen; i = i + 1) begin
			b = tbytes[i];
			if (tsync[i])
				chan[i] = 16'h4489;
			else
				chan[i] = {!prev && !b[7], b[7], !b[7] && !b[6], b[6], !b[6] && !b[5], b[5], !b[5] && !b[4], b[4],
				           !b[4] && !b[3], b[3], !b[3] && !b[2], b[2], !b[2] && !b[1], b[1], !b[1] && !b[0], b[0]};
			prev = b[0];
		end
	end
endtask

// the disk turns: flux transitions (200 ns pulses, jitter 0..120 ns), index pulse 1 ms per revolution
real CELL = 2000.0 * SPEED;
integer seed = 1;
initial begin : disk
	integer i, k, j;
	#1;
	build_track;
	forever begin
		FDC_INDEX = 1'b1;
		fork begin #1000000; FDC_INDEX = 1'b0; end join_none
		for (i = 0; i < tlen; i = i + 1)
			for (k = 15; k >= 0; k = k - 1)
				if (chan[i][k]) begin
					j = {$random(seed)} % 121;
					#(j); FDC_RDATA = 1'b1; #200; FDC_RDATA = 1'b0; #(CELL - 200 - j);
				end else
					#(CELL);
	end
end

// ---- the written stream decoded back: cells of 2 us, sync 4489 x 3, FB, 256 bytes, CRC ----
reg [7:0] wbuf [0:255];
reg [7:0] wgot [0:257];
integer wcount = 0, wstate = 0, wbits = 0;
reg [47:0] wsr = 48'd0;
realtime wprev = 0;
reg wfirst = 1'b1;
function [7:0] mfm_data(input [15:0] w);
	mfm_data = {w[14], w[12], w[10], w[8], w[6], w[4], w[2], w[0]};
endfunction
always @(negedge FDC_WG) wfirst = 1'b1;
always @(posedge FDC_WR_DATA) if (FDC_WG) begin : wdec
	integer n, i;
	if (wfirst) begin
		wfirst = 1'b0; wstate = 0;
		n = 1;
	end else
		n = ($realtime - wprev) / 2000.0;   // number of cells since the last transition (real -> integer rounds)
	wprev = $realtime;
	for (i = 0; i < n; i = i + 1) begin
		wsr = {wsr[46:0], i == n - 1};
		if (wstate == 0) begin
			if (wsr == {16'h4489, 16'h4489, 16'h4489}) begin wstate = 1; wbits = 0; end
		end else begin
			wbits = wbits + 1;
			if (wbits == 16) begin
				wbits = 0;
				if (wstate == 1) begin
					if (mfm_data(wsr[15:0]) != 8'hFB) begin
						$display("tb_hrdy_fdc: written mark %h, expected FB", mfm_data(wsr[15:0]));
						errors = errors + 1;
					end
					wstate = 2; wcount = 0;
				end else if (wstate == 2 && wcount < 258) begin
					wgot[wcount] = mfm_data(wsr[15:0]);
					wcount = wcount + 1;
				end
			end
		end
	end
end

// ---- CPU cycles ----
task io_wr(input ff, input [1:0] r, input [7:0] v);
	begin
		@(posedge clk);
		a = {9'h000, r, 5'b11111}; d = v;
		iorq_n = 1'b0; cs_n = ff; csff_n = !ff;
		@(posedge clk); wr_n = 1'b0;
		repeat (10) begin @(posedge clk); if (busy) waits = waits + 1; end
		while (busy) begin @(posedge clk); waits = waits + 1; end   // WAIT
		wr_n = 1'b1;
		@(posedge clk); iorq_n = 1'b1; cs_n = 1'b1; csff_n = 1'b1;
		repeat (3) @(posedge clk);
	end
endtask

task io_rd(input ff, input [1:0] r, output [7:0] v);
	begin
		@(posedge clk);
		a = {9'h000, r, 5'b11111};
		iorq_n = 1'b0; cs_n = ff; csff_n = !ff;
		@(posedge clk); rd_n = 1'b0;
		repeat (10) begin @(posedge clk); if (busy) waits = waits + 1; end
		while (busy) begin @(posedge clk); waits = waits + 1; end   // WAIT
		v = dout;
		rd_n = 1'b1;
		@(posedge clk); iorq_n = 1'b1; cs_n = 1'b1; csff_n = 1'b1;
		repeat (3) @(posedge clk);
	end
endtask

reg [7:0] st;
task wait_intrq(input integer ms);
	realtime t;
	begin
		t = $realtime;
		st = 8'h00;
		while (!st[7] && $realtime - t < ms * 1000000.0) io_rd(1, 0, st);
		if (!st[7]) begin $display("tb_hrdy_fdc: no INTRQ in %0d ms", ms); errors = errors + 1; end
	end
endtask

// ---- the test ----
initial begin : test
	integer i, n;
	reg [7:0] v;
	reg [15:0] crc;
	realtime t;
	repeat (20) @(posedge clk);
	reset = 1'b0;
	io_wr(1, 0, 8'h00);                  // #FF: /MR low
	repeat (50) @(posedge clk);
	io_wr(1, 0, 8'h3C);                  // #FF: drive A, /MR high, HLT, side 0

	// Restore, h = 1, rate 6 ms (3 ms with TurboFDC)
	io_wr(0, 0, 8'h08);
	wait_intrq(100);
	io_rd(0, 0, v);
	$display("tb_hrdy_fdc: restore: %0d steps, step period %.2f ms, track %0d, status %h", steps,
	         (step_t1 - step_t0) / 1000000.0, track, v);
	if (steps != 3 || track != 0) errors = errors + 1;
	if ((step_t1 - step_t0) < 2.9e6 || (step_t1 - step_t0) > 3.1e6) errors = errors + 1;
	if (v[0] || !v[2]) errors = errors + 1;   // busy, TR00

	// Poll: the loop of TR-DOS at #3FD5, 51 T: IN A,(#FF) and 47 T of other instructions
	waits = 0;
	t = $realtime;
	for (i = 0; i < 64; i = i + 1) begin
		io_rd(1, 0, v);
		repeat (TURBO ? 47 : 47 * 8) @(posedge clk);
	end
	t = ($realtime - t) / 64.0 / (CLK_HALF * 2.0);   // clocks per turn
	$display("tb_hrdy_fdc: poll: %.0f clocks per turn, %0d clocks of WAIT", t, waits);
	// the turn of the 3.5 MHz CPU: the 47 T + the access of the tb (17 clocks, 5 of them out of the decoders)
	if (TURBO) begin
		if (t < (47 + 5) * 8 * 0.97 || t > (47 + 5) * 8 * 1.1) errors = errors + 1;
	end else if (waits != 0) errors = errors + 1;

	// Read Sector 1
	io_wr(0, 2, 8'h01);
	io_wr(0, 0, 8'h80);
	n = 0; st = 8'h00;
	t = $realtime;
	while (!st[7] && $realtime - t < 200.0e6) begin
		io_rd(1, 0, st);
		repeat (GAP) @(posedge clk);
		if (st[6]) begin
			io_rd(0, 3, v);
			repeat (GAP) @(posedge clk);
			if (n < 256 && v !== sector[n]) begin
				if (errors < 10) $display("tb_hrdy_fdc: read byte %0d = %h, expected %h", n, v, sector[n]);
				errors = errors + 1;
			end
			n = n + 1;
		end
	end
	io_rd(0, 0, v);
	$display("tb_hrdy_fdc: read sector: %0d bytes, status %h", n, v);
	if (n != 256 || v != 8'h00) errors = errors + 1;

	// Write Sector 1
	for (i = 0; i < 256; i = i + 1) wbuf[i] = 8'hFF - i * 3;
	io_wr(0, 2, 8'h01);
	io_wr(0, 0, 8'hA0);
	n = 0; st = 8'h00;
	t = $realtime;
	while (!st[7] && $realtime - t < 200.0e6) begin
		io_rd(1, 0, st);
		repeat (GAP) @(posedge clk);
		if (st[6]) begin
			io_wr(0, 3, n < 256 ? wbuf[n] : 8'h00);
			repeat (GAP) @(posedge clk);
			n = n + 1;
		end
	end
	io_rd(0, 0, v);
	repeat (2000) @(posedge clk);
	crc = 16'hFFFF;
	crc = crc_byte(crc, 8'hA1); crc = crc_byte(crc, 8'hA1); crc = crc_byte(crc, 8'hA1); crc = crc_byte(crc, 8'hFB);
	for (i = 0; i < 256; i = i + 1) crc = crc_byte(crc, wbuf[i]);
	$display("tb_hrdy_fdc: write sector: %0d bytes, status %h, %0d bytes decoded from WDATA", n, v, wcount);
	if (n != 256 || v != 8'h00 || wcount != 258) errors = errors + 1;
	for (i = 0; i < 256; i = i + 1)
		if (wgot[i] !== wbuf[i]) begin
			if (errors < 10) $display("tb_hrdy_fdc: written byte %0d = %h, expected %h", i, wgot[i], wbuf[i]);
			errors = errors + 1;
		end
	if ({wgot[256], wgot[257]} !== crc) begin
		$display("tb_hrdy_fdc: written CRC %h%h, expected %h", wgot[256], wgot[257], crc);
		errors = errors + 1;
	end

	$display("tb_hrdy_fdc: DS80=%0d SPEED=%.2f TURBO=%0d: %0d errors", DS80, SPEED, TURBO, errors);
	$finish;
end

endmodule
