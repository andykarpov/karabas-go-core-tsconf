`timescale 1ns / 1ps
/*
 tb_gs_top (ISim): gs_top (the GS with its read cache, sdram2p) with sdram_model (CL 3).
 The ROM loader writes the test ROM gs_memtest.bin (gs_memtest.asm) at 80000000 while the GS is held,
 one byte per 250 ns; then the GS runs it: its RAM, the pages, a write to a cached word, a write to the
 ROM; at the same time a model of the OPL4 reads and writes port 2 (its own words, checked), and the
 FL loader writes into port 2 as well. Prints the speed of the GS in the timed loop of the ROM (a
 Z80 at 14 MHz without waits = 14.0).
 Prints "tb_gs_top: 0 errors".
*/
module tb_gs_top;

localparam real T = 11.892;   // clk_sys 84.09 MHz

reg clk_sys = 1'b0;
always #(T / 2) clk_sys = ~clk_sys;
reg clk_bus = 1'b0;
integer div = 0;
always @(posedge clk_sys) begin
	div = (div + 1) % 3;
	if (div == 0) clk_bus <= 1'b1;
	if (div == 1) clk_bus <= 1'b0;
end
reg ce_14m = 1'b0;
always @(negedge clk_bus) ce_14m <= !ce_14m;

reg areset = 1'b1;
reg gs_reset = 1'b1;
reg loader_act = 1'b0, loader_wr = 1'b0;
reg [31:0] loader_a = 32'd0;
reg [7:0] loader_d = 8'd0;
reg fl_wr = 1'b0;
reg [31:0] fl_a = 32'd0;
reg [7:0] fl_d = 8'd0;

reg [21:0] opl_addr = 22'd0;
reg opl_req = 1'b0, opl_we = 1'b0;
reg [7:0] opl_wdata = 8'd0;
wire opl_ack;
wire [15:0] opl_rdata;

wire [15:0] dq;
wire [12:0] sa;
wire [1:0] ba, dqm;
wire nwe, nras, ncas, sclk;
wire gs_oe;
wire [7:0] gs_do;
wire [14:0] gs_l, gs_r;

gs_top dut (
	.clk_sys(clk_sys), .clk_bus(clk_bus), .ce(ce_14m), .reset(gs_reset), .areset(areset),
	.a(16'hFFFF), .di(8'hFF), .mreq_n(1'b1), .iorq_n(1'b1), .m1_n(1'b1), .rd_n(1'b1), .wr_n(1'b1),
	.oe(gs_oe), .do_bus(gs_do),
	.sdram_clk(sclk), .sdram_dq(dq), .sdram_a(sa), .sdram_dqm(dqm), .sdram_ba(ba),
	.sdram_we_n(nwe), .sdram_ras_n(nras), .sdram_cas_n(ncas),
	.loader_act(loader_act), .loader_a(loader_a), .loader_d(loader_d), .loader_wr(loader_wr),
	.fl_wr(fl_wr), .fl_a(fl_a), .fl_d(fl_d),
	.opl_addr(opl_addr), .opl_req(opl_req), .opl_we(opl_we), .opl_wdata(opl_wdata),
	.opl_ack(opl_ack), .opl_rdata(opl_rdata),
	.out_l(gs_l), .out_r(gs_r)
);

sdram_model #(.CLK_NS(T), .CL(3), .ROW_BITS(8)) sdr (
	.clk(clk_sys), .ba(ba), .a(sa), .dqm(dqm), .ras_n(nras), .cas_n(ncas), .we_n(nwe), .dq(dq)
);

integer errors = 0;

// ------------------------------------------------------------------ the ROM
reg [7:0] rom [0:255];
integer rom_n = 208;
integer i;
initial $readmemh("gs_memtest.hex", rom);

task load_byte(input [31:0] a, input [7:0] d);
	begin
		@(posedge clk_bus);
		loader_a <= a; loader_d <= d; loader_wr <= 1'b1;
		@(posedge clk_bus);
		loader_wr <= 1'b0;
		repeat (6) @(posedge clk_bus);     // 7 clk_bus = 250 ns per byte
	end
endtask

// ------------------------------------------------------------------ the OPL4 model on port 2
// sample RAM words 210000 + 2 * k (k < 64; the model keeps 8 row bits: 200000 would be row 0): written, then read and checked; the FL loader fills
// 0..255 (the ROM) at the same time
reg [15:0] opl_ref [0:63];
reg        opl_ok [0:63];
integer seed = 7, r, k, opl_n = 0, opl_reads = 0;
reg opl_run = 1'b0;
initial for (i = 0; i < 64; i = i + 1) opl_ok[i] = 1'b0;

always @(posedge clk_sys) begin
	if (opl_req && opl_ack) begin
		opl_req <= 1'b0;
		if (!opl_we) begin
			opl_reads = opl_reads + 1;
			if (opl_ok[k] && opl_rdata !== opl_ref[k]) begin
				errors = errors + 1;
				if (errors < 10) $display("tb_gs_top: OPL4 read %h: %h, expected %h", opl_addr, opl_rdata, opl_ref[k]);
			end
		end
	end else if (!opl_req && opl_run) begin
		r = $random(seed);
		if (r[3:0] == 0) begin           // about every 16 clocks
			k = r[9:4];
			opl_addr <= 22'h210000 + {k, r[10]};
			opl_we <= r[11] | !opl_ok[k];
			opl_wdata <= r[23:16];
			if (r[11] | !opl_ok[k]) begin
				if (!opl_ok[k]) opl_ref[k] = {r[23:16], r[23:16]};
				else if (r[10]) opl_ref[k][15:8] = r[23:16];
				else opl_ref[k][7:0] = r[23:16];
				// the other byte of a first write is not written yet: x in the model and here
				if (!opl_ok[k] && !r[10]) opl_ref[k][15:8] = 8'hxx;
				if (!opl_ok[k] && r[10]) opl_ref[k][7:0] = 8'hxx;
				opl_ok[k] = 1'b1;
			end
			opl_req <= 1'b1;
			opl_n = opl_n + 1;
		end
	end
end

// the FL loader: byte n of the file = n xor #A5, one per 250 ns
reg fl_run = 1'b0;
integer fl_n = 0;
initial begin
	wait (fl_run);
	for (fl_n = 0; fl_n < 256; fl_n = fl_n + 1) begin
		@(posedge clk_bus);
		fl_a <= fl_n; fl_d <= fl_n[7:0] ^ 8'hA5; fl_wr <= 1'b1;
		@(posedge clk_bus);
		fl_wr <= 1'b0;
		repeat (5) @(posedge clk_bus);
	end
end

function [7:0] fl_byte(input integer n);
	fl_byte = n[7:0] ^ 8'hA5;
endfunction

// ------------------------------------------------------------------ the result of the ROM
reg [7:0] res = 8'd0;
real t55 = 0.0, taa = 0.0;
always @(dut.gs.port_xx03_reg) begin
	res = dut.gs.port_xx03_reg;
	$display("tb_gs_top: port #03 = %h at %0.0f ns", res, $realtime);
	if (res == 8'h55) t55 = $realtime;
	if (res == 8'hAA) taa = $realtime;
end

initial begin
	repeat (20) @(posedge clk_sys);
	areset = 1'b0;
	wait (!dut.sdram.init);
	// the ROM, the GS held
	loader_act = 1'b1;
	for (i = 0; i < rom_n; i = i + 1) load_byte(32'h80000000 + i, rom[i]);
	loader_act = 1'b0;
	repeat (10) @(posedge clk_bus);
	opl_run = 1'b1;
	fl_run = 1'b1;
	gs_reset = 1'b0;
	wait (res == 8'hAA || (res != 8'h00 && res != 8'h55));
	repeat (100) @(posedge clk_bus);
	opl_run = 1'b0;
	repeat (100) @(posedge clk_bus);
	if (res != 8'hAA) begin
		errors = errors + 1;
		$display("tb_gs_top: the GS test failed: %h", res);
		// the window #4000 (GS byte 8000 + n: word 4000 + n / 2 = bank 0, row 20, column n / 2)
		k = 0;
		for (i = 0; i < 256; i = i + 1)
			if (k < 8 && (i[0] ? sdr.mem[19'h04000 + i / 2][15:8] : sdr.mem[19'h04000 + i / 2][7:0]) !== (i[7:0] ^ 8'h40 ^ 8'h5a)) begin
				k = k + 1;
				$display("tb_gs_top: #40%h = %h", i[7:0], i[0] ? sdr.mem[19'h04000 + i / 2][15:8] : sdr.mem[19'h04000 + i / 2][7:0]);
			end
	end
	// the FL bytes in the SDRAM: bank 2, row 0 (the model keeps 8 row bits)
	for (i = 0; i < 128; i = i + 1)
		if (sdr.mem[19'h40000 + i] !== {fl_byte(2 * i + 1), fl_byte(2 * i)}) begin
			errors = errors + 1;
			if (errors < 10) $display("tb_gs_top: FL word %0d: %h", i, sdr.mem[19'h40000 + i]);
		end
	if (sdr.errors != 0) begin
		errors = errors + sdr.errors;
		$display("tb_gs_top: %0d errors of the SDRAM model", sdr.errors);
	end
	// from OUT (3),#55 to OUT (3),#AA: LD C,4 7, the loop 4 x (7 + 255 x 17 + 12 + 4 + 12) - 5,
	// LD A,#AA 7, OUT 11 = 17500 T
	$display("tb_gs_top: GS %0.2f MHz in the timed loop (17500 T in %0.0f ns), OPL4 %0d accesses (%0d reads)",
		17500.0 / (taa - t55) * 1000.0, taa - t55, opl_n, opl_reads);
	$display("tb_gs_top: %0d errors", errors);
	$finish;
end

endmodule
