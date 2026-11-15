`timescale 1ns / 1ps
/*
 tb_sdram2p: sdram2p (rtl/ram) with sdram_model (CL 3): random reads and writes (word and byte) on both
 ports at once against a reference, port 1 from a clk_bus domain (clk_sys / 3, as the GS), port 2 from
 clk_sys (as the OPL4), on a few rows of all four banks; idle gaps for the refresh.
 Checks: every read word, the timing checks of the model (tRCD, tRP, tRC, tRAS, tWR, tRFC, closed
 banks, the mode register), DQ driven by both sides at once, the refresh interval
 (64 ms / 8192 = 7.8 us), and that every request is done within its bound.
*/
module tb_sdram2p;

localparam real T = 11.892;   // 84.09 MHz
localparam integer N_OPS = 20000;

reg clk = 1'b0;
always #(T / 2) clk = ~clk;
reg clk_bus = 1'b0;
integer div = 0;
always @(posedge clk) begin
	div = (div + 1) % 3;
	if (div == 0) clk_bus <= 1'b1;
	if (div == 1) clk_bus <= 1'b0;   // high for 1 clk_sys, low for 2: edges on clk_sys edges
end

wire [15:0] dq;
wire [12:0] sa;
wire [1:0] ba;
wire dqml, dqmh, nwe, nras, ncas, sclk;
reg init_n = 1'b0;

reg p1_req = 0, p1_we = 0; reg [23:1] p1_a = 0; reg [1:0] p1_ds = 0; reg [15:0] p1_d = 0;
wire p1_ack; wire [15:0] p1_q;
reg p2_req = 0, p2_we = 0; reg [23:1] p2_a = 0; reg [1:0] p2_ds = 0; reg [15:0] p2_d = 0;
wire p2_ack; wire [15:0] p2_q;

sdram2p dut (
	.SDRAM_DQ(dq), .SDRAM_A(sa), .SDRAM_DQML(dqml), .SDRAM_DQMH(dqmh), .SDRAM_BA(ba),
	.SDRAM_nWE(nwe), .SDRAM_nRAS(nras), .SDRAM_nCAS(ncas), .SDRAM_CLK(sclk),
	.init_n(init_n), .clk(clk),
	.port1_req(p1_req), .port1_ack(p1_ack), .port1_we(p1_we), .port1_a(p1_a), .port1_ds(p1_ds),
	.port1_d(p1_d), .port1_q(p1_q),
	.port2_req(p2_req), .port2_ack(p2_ack), .port2_we(p2_we), .port2_a(p2_a), .port2_ds(p2_ds),
	.port2_d(p2_d), .port2_q(p2_q)
);

sdram_model #(.CLK_NS(T), .CL(3)) sdr (
	.clk(clk), .ba(ba), .a(sa), .dqm({dqmh, dqml}), .ras_n(nras), .cas_n(ncas), .we_n(nwe), .dq(dq)
);

// the address of an op: {bank bit, row (one of 4), column}; the reference index {port, bank, row, col}
reg [12:0] rowtab [0:3];
initial begin
	rowtab[0] = 13'h0000; rowtab[1] = 13'h0001; rowtab[2] = 13'h1abc; rowtab[3] = 13'h1fff;
end
reg [15:0] ref_mem [0:8191];
reg        ref_ok [0:8191];
integer i;
initial for (i = 0; i < 8192; i = i + 1) ref_ok[i] = 1'b0;

integer errors = 0;
task fail(input [8*40-1:0] what, input integer port, input [15:0] got, input [15:0] exp);
	begin
		errors = errors + 1;
		if (errors <= 10) $display("tb_sdram2p: port %0d %0s: got %h expected %h (t %0t)", port, what, got, exp, $time);
	end
endtask

// one port: a random op whenever idle
integer seed1 = 1, seed2 = 2;
integer n1 = 0, n2 = 0, r1, r2;
reg busy1 = 0, busy2 = 0;
reg [11:0] idx1, idx2;
integer wait1 = 0, wait2 = 0, max1 = 0, max2 = 0;
integer gap1 = 0, gap2 = 0;
reg [1:0] rs; reg [8:0] cs; reg bs;

function [15:0] merge(input [15:0] old, input [15:0] d, input [1:0] ds);
	merge = { ds[1] ? d[15:8] : old[15:8], ds[0] ? d[7:0] : old[7:0] };
endfunction

always @(posedge clk_bus) if (init_n && !dut.init) begin
	if (busy1) begin
		wait1 = wait1 + 1;
		if (p1_ack == p1_req) begin
			busy1 <= 1'b0;
			if (wait1 > max1) max1 = wait1;
			if (!p1_we && ref_ok[{1'b0, idx1}] && p1_q !== ref_mem[{1'b0, idx1}]) fail("read", 1, p1_q, ref_mem[{1'b0, idx1}]);
		end
	end else if (gap1 > 0) gap1 = gap1 - 1;
	else if (n1 < N_OPS) begin
		r1 = $random(seed1);
		bs = r1[0]; rs = r1[2:1]; cs = r1[11:3];
		idx1 = {bs, rs, cs};
		p1_a <= {bs, rowtab[rs], cs};
		p1_we <= r1[12] | !ref_ok[{1'b0, bs, rs, cs}];
		p1_ds <= (r1[12] | !ref_ok[{1'b0, bs, rs, cs}]) ? (ref_ok[{1'b0, bs, rs, cs}] ? (r1[14:13] == 0 ? 2'b11 : r1[14:13]) : 2'b11) : 2'b11;
		p1_d <= $random(seed1);
		busy1 <= 1'b1;
		wait1 = 0;
		p1_req <= ~p1_req;
		n1 = n1 + 1;
		if (r1[20:15] == 0) gap1 = 2000;   // now and then a long pause
	end
end
// the reference takes a write when it is issued (the read of the same port comes after it)
always @(p1_req) if (init_n && p1_we) begin
	#1;
	ref_mem[{1'b0, idx1}] = merge(ref_mem[{1'b0, idx1}], p1_d, p1_ds);
	ref_ok[{1'b0, idx1}] = 1'b1;
end

always @(posedge clk) if (init_n && !dut.init) begin
	if (busy2) begin
		wait2 = wait2 + 1;
		if (p2_ack == p2_req) begin
			busy2 <= 1'b0;
			if (wait2 > max2) max2 = wait2;
			if (!p2_we && ref_ok[{1'b1, idx2}] && p2_q !== ref_mem[{1'b1, idx2}]) fail("read", 2, p2_q, ref_mem[{1'b1, idx2}]);
		end
	end else if (gap2 > 0) gap2 = gap2 - 1;
	else if (n2 < N_OPS) begin
		r2 = $random(seed2);
		bs = r2[0]; rs = r2[2:1]; cs = r2[11:3];
		idx2 = {bs, rs, cs};
		p2_a <= {bs, rowtab[rs], cs};
		p2_we <= r2[12] | !ref_ok[{1'b1, bs, rs, cs}];
		p2_ds <= (r2[12] | !ref_ok[{1'b1, bs, rs, cs}]) ? (ref_ok[{1'b1, bs, rs, cs}] ? (r2[14:13] == 0 ? 2'b11 : r2[14:13]) : 2'b11) : 2'b11;
		p2_d <= $random(seed2);
		busy2 <= 1'b1;
		wait2 = 0;
		p2_req <= ~p2_req;
		n2 = n2 + 1;
		if (r2[20:16] == 0) gap2 = 6000;
	end
end
always @(p2_req) if (init_n && p2_we) begin
	#1;
	ref_mem[{1'b1, idx2}] = merge(ref_mem[{1'b1, idx2}], p2_d, p2_ds);
	ref_ok[{1'b1, idx2}] = 1'b1;
end

// DQ driven by both: the controller (dir = 0) while the SDRAM drives read data
integer contention = 0;
always @(negedge clk or posedge clk) #1 if (!dut.dir && sdr.v2) contention = contention + 1;

// the refresh interval
real t_last_ref = 0.0, max_gap = 0.0;
integer refs = 0;
always @(negedge clk) if ({nras, ncas, nwe} == 3'b001) begin
	if (refs > 0 && $realtime - t_last_ref > max_gap) max_gap = $realtime - t_last_ref;
	t_last_ref = $realtime;
	refs = refs + 1;
end

initial begin
	#(T * 20) init_n = 1'b1;
	wait (n1 == N_OPS && n2 == N_OPS && !busy1 && !busy2);
	#(T * 100);
	if (sdr.errors != 0) begin errors = errors + sdr.errors; $display("tb_sdram2p: %0d errors of the SDRAM model", sdr.errors); end
	if (contention != 0) begin errors = errors + 1; $display("tb_sdram2p: DQ driven by both sides in %0d half clocks", contention); end
	if (max_gap > 7800.0) begin errors = errors + 1; $display("tb_sdram2p: refresh gap %0.0f ns", max_gap); end
	// port 1 (clk_bus): up to a cycle to wait and one to do, plus the two cycles of an urgent refresh
	// (once in 7.4 us), one clk_bus to see it; port 2 (clk_sys): a cycle postponed for a port 1 read more
	if (max1 > 12) begin errors = errors + 1; $display("tb_sdram2p: port 1 took %0d clk_bus", max1); end
	if (max2 > 27) begin errors = errors + 1; $display("tb_sdram2p: port 2 took %0d clk_sys", max2); end
	$display("tb_sdram2p: %0d + %0d ops, %0d refreshes (gap up to %0.0f ns), port 1 up to %0d clk_bus, port 2 up to %0d clk_sys",
		n1, n2, refs, max_gap, max1, max2);
	$display("tb_sdram2p: %0d errors", errors);
	$finish;
end

endmodule
