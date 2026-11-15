`timescale 1ns / 1ps
/*
 tb_z80s_cen (iverilog): z80_silicon_cen.v (gen_cen.py) against z80-silicon as it is (Z80.v on the two
 edges of its own clock zc). The converted core runs on clk with cen_p / cen_n; zc rises at the clk edge
 of cen_p and falls at the one of cen_n, so both cores see the same edges. Each has its own 64K memory
 (random bytes), written at a clk edge while WR; an opcode fetch takes a random stream (every
 instruction, HALT, IN / OUT, prefixes, no loops); the data of an I/O read and of an interrupt acknowledge is a function of the address. INT, NMI, WAIT and BUSRQ
 random, changed at the falling clk. The enables follow PATTERN:
   0  cen_p and cen_n in alternate clocks (14 MHz of zclock at 28 MHz)
   1  two clocks a half (7 MHz)
   2  four clocks a half (3.5 MHz)
   3  random gaps of 0..3 clocks (the stall of zclock)
 Every output of the two cores is compared at each clk edge. Prints "tb_z80s_cen: 0 errors".
*/
module tb_z80s_cen;
parameter integer PATTERN = 0;
parameter integer CYCLES = 200000;     // Z80 clock cycles
parameter integer SEED = 1;

reg clk = 1'b0;
always #5 clk = ~clk;

// the enables, changed at the falling clk
reg cen_p = 1'b0, cen_n = 1'b0;
reg phase = 1'b0;                      // 0: the next is cen_p
integer gap = 0, seed = SEED, ncyc = 0;
always @(negedge clk) begin
	cen_p <= 1'b0; cen_n <= 1'b0;
	if (gap > 0) gap = gap - 1;
	else begin
		if (!phase) cen_p <= 1'b1; else begin cen_n <= 1'b1; ncyc = ncyc + 1; end
		phase = !phase;
		case (PATTERN)
		0: gap = 0;
		1: gap = 1;
		2: gap = 3;
		default: gap = $unsigned($random(seed)) % 4;
		endcase
	end
end
reg zc = 1'b0;                         // the clock of the original
always @(posedge clk) begin
	if (cen_p) zc <= 1'b1;
	if (cen_n) zc <= 1'b0;
end

// inputs of both, at the falling clk
reg reset = 1'b1, p_int = 1'b0, nmi = 1'b0, p_wait = 1'b0, busrq = 1'b0;
integer iseed = SEED * 7 + 3;
always @(negedge clk) if (ncyc > 20) begin
	reset  <= 1'b0;
	p_int  <= ($unsigned($random(iseed)) % 4000) < 30 ? 1'b1 : (p_int && ($unsigned($random(iseed)) % 64 != 0));
	nmi    <= ($unsigned($random(iseed)) % 3000) == 0;
	p_wait <= ($unsigned($random(iseed)) % 16) == 0;
	busrq  <= ($unsigned($random(iseed)) % 3000) == 0 ? 1'b1 : (busrq && ($unsigned($random(iseed)) % 32 != 0));
end

// two identical memories
reg [7:0] mem_r [0:65535];
reg [7:0] mem_d [0:65535];
integer i, mseed = SEED * 13 + 1;
initial for (i = 0; i < 65536; i = i + 1) begin mem_r[i] = $random(mseed); mem_d[i] = mem_r[i]; end

wire [7:0] do_r, do_d;
wire [15:0] a_r, a_d;
wire mreq_r, iorq_r, rd_r, wr_r, dz_r, az_r, cz_r, rfsh_r, m1_r, halt_r, busack_r;
wire mreq_d, iorq_d, rd_d, wr_d, dz_d, az_d, cz_d, rfsh_d, m1_d, halt_d, busack_d;
function [7:0] io_val(input [15:0] a); io_val = a[7:0] ^ {a[14:8], a[15]} ^ 8'h5A; endfunction
// an opcode fetch (M1 read) takes the next byte of a random stream, not the memory: no loops, every
// instruction in turn (the opcode refetch of a block instruction too); each core has its own count of
// M1 cycles, the same while the two agree
function [7:0] op_val(input [31:0] n);
	reg [31:0] h;
	begin h = n * 32'h9E3779B1; h = h ^ (h >> 15); h = h * 32'h85EBCA77; op_val = h[23:16] ^ h[7:0];
		if (op_val == 8'h76 && h[30:28] != 3'd0) op_val = 8'h00;   // HALT rarer: with DI it waits for an NMI
	end
endfunction
integer opn_r = 0, opn_d = 0;
reg m1f_r = 1'b0, m1f_d = 1'b0;
always @(negedge clk) begin
	if (m1f_r && !m1_r) opn_r = opn_r + 1;
	if (m1f_d && !m1_d) opn_d = opn_d + 1;
	m1f_r = m1_r; m1f_d = m1_d;
end
wire [7:0] di_r = iorq_r ? io_val(a_r) : (m1_r && rd_r) ? op_val(opn_r + SEED * 1000003) : mem_r[a_r];
wire [7:0] di_d = iorq_d ? io_val(a_d) : (m1_d && rd_d) ? op_val(opn_d + SEED * 1000003) : mem_d[a_d];
always @(posedge clk) begin
	if (mreq_r && wr_r) mem_r[a_r] <= do_r;
	if (mreq_d && wr_d) mem_d[a_d] <= do_d;
end

Z80 u_ref (.clk(zc), .data_in(di_r), .data_out(do_r), .adr(a_r), .mreq(mreq_r), .iorq(iorq_r), .rd(rd_r),
	.wr(wr_r), .data_z(dz_r), .adr_z(az_r), .controls_z(cz_r), .rfsh(rfsh_r), .p_m1(m1_r), .halt(halt_r),
	.p_wait(p_wait), .p_int(p_int), .nmi(nmi), .reset(reset), .busrq(busrq), .busack(busack_r));
z80s_Z80 dut (.clk(clk), .cen_p(cen_p), .cen_n(cen_n), .data_in(di_d), .data_out(do_d), .adr(a_d),
	.mreq(mreq_d), .iorq(iorq_d), .rd(rd_d), .wr(wr_d), .data_z(dz_d), .adr_z(az_d), .controls_z(cz_d),
	.rfsh(rfsh_d), .p_m1(m1_d), .halt(halt_d), .p_wait(p_wait), .p_int(p_int), .nmi(nmi), .reset(reset),
	.busrq(busrq), .busack(busack_d));

wire [36:0] o_r = {do_r, a_r, mreq_r, iorq_r, rd_r, wr_r, dz_r, az_r, cz_r, rfsh_r, m1_r, halt_r, busack_r};
wire [36:0] o_d = {do_d, a_d, mreq_d, iorq_d, rd_d, wr_d, dz_d, az_d, cz_d, rfsh_d, m1_d, halt_d, busack_d};

// activity, so a core stuck in HALT or in X does not pass
integer errors = 0, m1s = 0, ios = 0, wrs = 0, ints = 0, halts = 0, xs = 0;
reg m1_q = 1'b0, iorq_q = 1'b0, wr_q = 1'b0, halt_q = 1'b0;
always @(negedge clk) if (!reset) begin
	if (o_r !== o_d) begin
		errors = errors + 1;
		if (errors <= 10)
			$display("tb_z80s_cen: cycle %0d: ref %h dut %h", ncyc, o_r, o_d);
	end
	if (^o_r === 1'bx) xs = xs + 1;
	if (m1_r && !m1_q) m1s = m1s + 1;
	if (iorq_r && !iorq_q) begin ios = ios + 1; if (m1_r) ints = ints + 1; end
	if (wr_r && !wr_q) wrs = wrs + 1;
	if (halt_r && !halt_q) halts = halts + 1;
	m1_q = m1_r; iorq_q = iorq_r; wr_q = wr_r; halt_q = halt_r;
	if (ncyc >= CYCLES) begin
		$display("tb_z80s_cen: pattern %0d: %0d Z80 cycles, %0d M1, %0d writes, %0d I/O (%0d INT ack), %0d HALT, %0d clocks with X",
			PATTERN, ncyc, m1s, wrs, ios, ints, halts, xs);
		if (m1s < CYCLES / 20 || wrs == 0 || ints == 0) begin
			errors = errors + 1;
			$display("tb_z80s_cen: too little activity");
		end
		$display("tb_z80s_cen: %0d errors", errors);
		$finish;
	end
end
endmodule
