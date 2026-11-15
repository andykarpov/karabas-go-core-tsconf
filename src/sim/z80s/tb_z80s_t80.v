`timescale 1ns / 1ps
/*
 tb_z80s_t80 (Verilator): z80-silicon (z80_silicon_cen.v) and T80pa (a ghdl --synth netlist, the one of
 tsconf.v) side by side on one clk with the enables of tsconf (CEN_p = zpos, CEN_n = zneg; PATTERN as in
 tb_z80s_cen: 0 14 MHz, 1 7 MHz, 2 3.5 MHz, 3 random gaps). Same inputs: each has its own memory (the
 same random bytes), an opcode fetch takes the opcode of its own M1 count (op_at: a prologue that loads
 every register, then groups of PERIOD: random opcodes and two NOPs), INT / NMI / WAIT random (INPUTS,
 CLEAN), BUSRQ with BUSRQ = 1. OUT0 = OUT0 (tsconf: 1, OUT (C),255; NMOS: 0).
 Checks: (1) at each clk the bus of both {A, DO while WR, MREQ, IORQ, RD, WR, M1, RFSH, HALT, BUSACK, R
 at the refresh}: per signal the clocks it differs, the first MAXSHOW differences; at the first difference
 of an address or of the written data the two run different programs (DIVERGED, STOP_ON stops there).
 (2) the registers at the end of the second NOP of each group (the results of both are written then, the
 NOP writes nothing; the silicon core is mapped through its bank switches), STOP_REG stops there with the
 opcodes before. An INT / NMI response that falls on that NOP gives a register difference of a moment
 (SP), not a bus one: with INT / NMI the bus is the check (STOP_REG = 0).
 The differences found (2026-11-15), all T80pa against the chip (z80-silicon passes ZEXALL, z80full,
 z80ccf): SKIP bits 0..3 below; INT sampled at T1 of the next M1, a clock after the chip (an INT that
 ends in the last T state is taken by the chip, not by T80pa; CLEAN = 1 keeps away from it); NMI taken an
 instruction earlier when it rises late in an instruction; EI then NMI leaves IFF1 = 1 in T80pa (an INT
 is taken at 0066); IM 0 with a two-byte instruction (T80pa moves PC; ACK_FF = 1 gives RST 38); HALT
 output half a clock later; IORQ in the first M1 after power on (IntCycleD_n of T80pa starts at 0).
 The bus timing of every instruction, of WAIT and of the INT acknowledge is the same.
*/
module tb_z80s_t80;
parameter integer PATTERN = 0;
parameter integer CYCLES = 200000;
parameter integer SEED = 1;
parameter integer OUT0 = 0;
parameter integer BUSRQ = 0;
parameter integer MAXSHOW = 12;
parameter integer STOP_ON = 1;
parameter integer REGF = 1;            // 1: compare F as it is (0: only without X / Y, F-XY)
parameter integer STOP_REG = 1;        // stop at the first register difference
parameter integer TRACE_FROM = -1;     // Z80 cycles to print the bus of both at each clock
parameter integer TRACE_TO = -1;
parameter integer CLEAN = 0;            // 1: INT and NMI rise at the start of an M1 (not in the last T state of an
                                       // instruction, where T80pa samples them a clock later than the chip), INT
                                       // held until its acknowledge
parameter integer ACK_FF = 1;           // 1: the data of an INT acknowledge is FF (RST 38 in IM 0, the frame vector of
                                       // TS-Conf in IM 2), 0: the I/O value (other IM 0 instructions: below)
parameter integer SKIP = 0;             // the known differences of T80pa out of the stream (bits):
                                       //  0 SCF / CCF (X / Y of T80pa from A only; the chip: A | F after an
                                       //    instruction that left F, A after one that changed it)
                                       //  1 DD / FD + INC / DEC BC, DE, SP (T80pa: another register pair,
                                       //    T80.vhd RegAddrA with XY_State /= 00)
                                       //  2 ED + LDIR / CPIR / INIR / OTIR / LDDR / CPDR / INDR / OTDR (X / Y of
                                       //    a repeat: the chip takes them from PC, T80pa not)
                                       //  3 CB + BIT n,(HL) (X / Y from MEMPTR, which T80pa keeps otherwise)
parameter integer HALTS = 0;           // 1: HALT in the random stream (1 in 8 of its 76)
parameter integer INPUTS = 7;          // the random inputs: bit 0 INT, 1 NMI, 2 WAIT
parameter integer T80_RST = 2;         // Z80 cycles the reset of T80pa is longer: the silicon core takes
                                       // two more after its reset (as the chip), the first M1 then together

reg clk = 1'b0;
always #5 clk = ~clk;

reg cen_p = 1'b0, cen_n = 1'b0;
reg phase = 1'b0;
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

reg reset_t = 1'b1;
always @(negedge clk) if (ncyc > 20 + T80_RST) reset_t <= 1'b0;
reg reset = 1'b1, p_int = 1'b0, nmi = 1'b0, p_wait = 1'b0, busrq = 1'b0;
integer iseed = SEED * 7 + 3, nmi_cnt = 0;
reg m1_c = 1'b0;                       // m1 of the silicon core a clock before (the start of an M1)
always @(negedge clk) m1_c <= m1_s;
always @(negedge clk) if (ncyc > 20) begin
	reset  <= 1'b0;
	if ((INPUTS & 1) && CLEAN) begin
		if (iorq_s && m1_s) p_int <= 1'b0;
		else if (m1_s && !m1_c && ($unsigned($random(iseed)) % 40) == 0) p_int <= 1'b1;
	end else if (INPUTS & 1)
		p_int  <= ($unsigned($random(iseed)) % 4000) < 30 ? 1'b1 : (p_int && ($unsigned($random(iseed)) % 64 != 0));
	if (INPUTS & 2) begin              // NMI held 16..79 clocks (an edge, as the button / OSD of tsconf)
		if (nmi_cnt > 0) nmi_cnt = nmi_cnt - 1;
		else if ((!CLEAN || (m1_s && !m1_c)) && ($unsigned($random(iseed)) % (CLEAN ? 400 : 6000)) == 0)
			nmi_cnt = 16 + $unsigned($random(iseed)) % 64;
		nmi <= nmi_cnt > 0;
	end
	if (INPUTS & 4)
		p_wait <= ($unsigned($random(iseed)) % 16) == 0;
	if (BUSRQ)
		busrq <= ($unsigned($random(iseed)) % 3000) == 0 ? 1'b1 : (busrq && ($unsigned($random(iseed)) % 32 != 0));
end

reg [7:0] mem_s [0:65535];
reg [7:0] mem_t [0:65535];
integer i, mseed = SEED * 13 + 1;
initial for (i = 0; i < 65536; i = i + 1) begin mem_s[i] = $random(mseed); mem_t[i] = mem_s[i]; end

function [7:0] io_val(input [15:0] a); io_val = a[7:0] ^ {a[14:8], a[15]} ^ 8'h5A; endfunction
// the first opcodes: every register from the memory (after a reset they differ: T80pa clears them, the
// chip and the silicon core do not), then the random stream
localparam integer NPRE = 22;
reg [7:0] pre [0:NPRE - 1];
initial begin
	pre[0] = 8'h31; pre[1] = 8'h01; pre[2] = 8'h11; pre[3] = 8'h21;            // LD SP / BC / DE / HL,nn
	pre[4] = 8'hDD; pre[5] = 8'h21; pre[6] = 8'hFD; pre[7] = 8'h21;            // LD IX / IY,nn
	pre[8] = 8'hF1; pre[9] = 8'hD9; pre[10] = 8'h01; pre[11] = 8'h11;          // POP AF, EXX, LD BC' / DE'
	pre[12] = 8'h21; pre[13] = 8'h08; pre[14] = 8'hF1; pre[15] = 8'hED;        // LD HL', EX AF,AF', POP AF
	pre[16] = 8'h47; pre[17] = 8'hED; pre[18] = 8'h4F; pre[19] = 8'h3A;        // LD I,A, LD R,A, LD A,(nn) (WZ)
	pre[20] = 8'hF1; pre[21] = 8'h00;                                          // POP AF
end
function [7:0] op_val(input [31:0] n);
	reg [31:0] h;
	begin h = n * 32'h9E3779B1; h = h ^ (h >> 15); h = h * 32'h85EBCA77; op_val = h[23:16] ^ h[7:0];
		if (op_val == 8'h76 && (HALTS == 0 || h[30:28] != 3'd0)) op_val = 8'h00;
		if ((SKIP & 1) && (op_val == 8'h37 || op_val == 8'h3F)) op_val = 8'h00;
	end
endfunction

// silicon
wire [7:0] do_s; wire [15:0] a_s;
wire mreq_s, iorq_s, rd_s, wr_s, rfsh_s, m1_s, halt_s, busack_s;
// T80pa (active low)
wire [7:0] do_t; wire [15:0] a_t;
wire [211:0] reg_t;
wire mreq_tn, iorq_tn, rd_tn, wr_tn, rfsh_tn, m1_tn, halt_tn, busak_tn;
wire mreq_t = !mreq_tn, iorq_t = !iorq_tn, rd_t = !rd_tn, wr_t = !wr_tn, rfsh_t = !rfsh_tn, m1_t = !m1_tn,
	halt_t = !halt_tn, busack_t = !busak_tn;

integer opn_s = 0, opn_t = 0;
reg m1f_s = 1'b0, m1f_t = 1'b0;
reg [7:0] hist [0:7];                  // the last opcodes of the silicon core
always @(negedge clk) begin
	if (m1f_s && !m1_s) opn_s = opn_s + 1;
	if (m1f_t && !m1_t) opn_t = opn_t + 1;
	m1f_s = m1_s; m1f_t = m1_t;
end
// the opcode of M1 number n: the prologue, then groups of PERIOD: PERIOD - 2 random opcodes (the last of
// them not a prefix) and two NOPs; the registers are compared at the end of the second NOP (both cores
// have written the results before it, a NOP writes nothing)
parameter integer PERIOD = 5;
function [7:0] op_at(input integer n);
	integer m;
	reg [7:0] o, p;
	begin
		m = n - NPRE;
		if (n < NPRE) op_at = pre[n];
		else if (m % PERIOD >= PERIOD - 2) op_at = 8'h00;
		else begin
			o = op_val(n + SEED * 1000003);
			p = (m % PERIOD == 0) ? 8'h00 : op_val(n - 1 + SEED * 1000003);
			if ((SKIP & 2) && (p == 8'hDD || p == 8'hFD) && (o == 8'h03 || o == 8'h0B || o == 8'h13 || o == 8'h1B ||
				o == 8'h33 || o == 8'h3B)) o = 8'h00;
			if ((SKIP & 8) && p == 8'hCB && o[7:6] == 2'b01 && o[2:0] == 3'd6) o = 8'h00;
			if ((SKIP & 4) && p == 8'hED && (o[7:4] == 4'hB && o[2] == 1'b0)) o = 8'h00;
			if (m % PERIOD == PERIOD - 3 && (o == 8'hCB || o == 8'hDD || o == 8'hED || o == 8'hFD)) o = 8'h00;
			op_at = o;
		end
	end
endfunction
function check_at(input integer n);
	check_at = n >= NPRE + PERIOD && (n - NPRE) % PERIOD == PERIOD - 1;
endfunction
wire [7:0] di_s = (m1_s && rd_s && mreq_s) ? op_at(opn_s) : iorq_s ? ((m1_s && ACK_FF) ? 8'hFF : io_val(a_s)) : mem_s[a_s];
wire [7:0] di_t = (m1_t && rd_t && mreq_t) ? op_at(opn_t) : iorq_t ? ((m1_t && ACK_FF) ? 8'hFF : io_val(a_t)) : mem_t[a_t];
// not in the reset: WR_n / MREQ_n of T80pa start at 0 (no initial value, 0 in the FPGA too) until the
// first clock of its reset
always @(posedge clk) begin
	if (mreq_s && wr_s && !reset) mem_s[a_s] <= do_s;
	if (mreq_t && wr_t && !reset_t) mem_t[a_t] <= do_t;
end

z80s_Z80 sil (.clk(clk), .cen_p(cen_p), .cen_n(cen_n), .data_in(di_s), .data_out(do_s), .adr(a_s),
	.mreq(mreq_s), .iorq(iorq_s), .rd(rd_s), .wr(wr_s), .data_z(), .adr_z(), .controls_z(),
	.rfsh(rfsh_s), .p_m1(m1_s), .halt(halt_s), .p_wait(p_wait), .p_int(p_int), .nmi(nmi), .reset(reset),
	.busrq(busrq), .busack(busack_s));
T80pa t80 (.RESET_n(!reset_t), .CLK(clk), .CEN_p(cen_p), .CEN_n(cen_n), .WAIT_n(!p_wait), .INT_n(!p_int),
	.NMI_n(!nmi), .BUSRQ_n(!busrq), .OUT0(OUT0 != 0), .DI(di_t), .R800_mode(1'b0), .DIRSet(1'b0), .DIR(212'd0),
	.M1_n(m1_tn), .MREQ_n(mreq_tn), .IORQ_n(iorq_tn), .RD_n(rd_tn), .WR_n(wr_tn), .RFSH_n(rfsh_tn),
	.HALT_n(halt_tn), .BUSAK_n(busak_tn), .A(a_t), .DO(do_t), .REG(reg_t));

// the opcode history (at the end of each M1 of the silicon core)
reg [7:0] cur_op = 8'h00;
always @(negedge clk) if (m1_s && rd_s && mreq_s) cur_op = di_s;
reg m1q = 1'b0;
always @(negedge clk) begin
	if (m1q && !m1_s && !iorq_s) begin
		for (i = 7; i > 0; i = i - 1) hist[i] = hist[i - 1];
		hist[0] = cur_op;
	end
	m1q = m1_s;
end


// ---- the registers after each M1, at the end of its refresh (T4): both write the last result of an
// instruction during the next M1 (as the chip), this one has written nothing yet; both as in REG of T80pa: IFF2 IFF1 IM IY HL' DE' BC' IX HL
// DE BC PC SP R I F' A' F A. The silicon core swaps no contents: EX AF / EXX / EX DE,HL toggle a
// switch each (register_selector), the registers are mapped through them here.
`define SR sil.registers
`define SS sil.register_selector
wire [15:0] s_af0 = {`SR.reg_a, `SR.reg_f}, s_af1 = {`SR.reg_a_, `SR.reg_f_};
wire [15:0] s_bc0 = {`SR.reg_b, `SR.reg_c}, s_bc1 = {`SR.reg_b_, `SR.reg_c_};
wire [15:0] s_hl0 = {`SR.reg_h, `SR.reg_l}, s_hl1 = {`SR.reg_h_, `SR.reg_l_};
wire [15:0] s_de0 = {`SR.reg_d, `SR.reg_e}, s_de1 = {`SR.reg_d_, `SR.reg_e_};
wire s_exde0 = `SS.switch_exde_base, s_exde1 = `SS.switch_exde_alt;
// the main set: the bank with switch_exx = 1 is the unprimed registers (sel_bc = sel_bc_set & switch_exx)
wire [15:0] s_bc  = `SS.switch_exx ? s_bc0 : s_bc1;
wire [15:0] s_bc_ = `SS.switch_exx ? s_bc1 : s_bc0;
wire [15:0] s_hlm = `SS.switch_exx ? (s_exde0 ? s_de0 : s_hl0) : (s_exde1 ? s_de1 : s_hl1);
wire [15:0] s_dem = `SS.switch_exx ? (s_exde0 ? s_hl0 : s_de0) : (s_exde1 ? s_hl1 : s_de1);
wire [15:0] s_hla = `SS.switch_exx ? (s_exde1 ? s_de1 : s_hl1) : (s_exde0 ? s_de0 : s_hl0);
wire [15:0] s_dea = `SS.switch_exx ? (s_exde1 ? s_hl1 : s_de1) : (s_exde0 ? s_hl0 : s_de0);
wire [15:0] s_af  = `SS.switch_exaf ? s_af0 : s_af1;
wire [15:0] s_af_ = `SS.switch_exaf ? s_af1 : s_af0;
wire [1:0] s_im = {sil.im_logic.im_bit1, sil.im_logic.im_bit0} == 2'b11 ? 2'd2 :
	{sil.im_logic.im_bit1, sil.im_logic.im_bit0} == 2'b10 ? 2'd1 : 2'd0;
wire [211:0] reg_s = {sil.interrupt_logic.iff2, sil.interrupt_logic.iff1, s_im,
	{`SR.reg_iyh, `SR.reg_iyl}, s_hla, s_dea, s_bc_, {`SR.reg_ixh, `SR.reg_ixl}, s_hlm, s_dem, s_bc,
	{`SR.reg_pch, `SR.reg_pcl}, {`SR.reg_sph, `SR.reg_spl}, `SR.reg_r, `SR.reg_i, s_af_[7:0], s_af_[15:8],
	s_af[7:0], s_af[15:8]};

localparam integer NR = 20;
reg [8*8-1:0] rn [0:NR - 1];
integer rlo [0:NR - 1], rw [0:NR - 1], rdiff [0:NR - 1];
initial begin
	rn[0] = "A";   rlo[0] = 0;   rw[0] = 8;   rn[1] = "F";   rlo[1] = 8;   rw[1] = 8;
	rn[2] = "A'";  rlo[2] = 16;  rw[2] = 8;   rn[3] = "F'";  rlo[3] = 24;  rw[3] = 8;
	rn[4] = "I";   rlo[4] = 32;  rw[4] = 8;   rn[5] = "R";   rlo[5] = 40;  rw[5] = 8;
	rn[6] = "SP";  rlo[6] = 48;  rw[6] = 16;  rn[7] = "PC";  rlo[7] = 64;  rw[7] = 16;
	rn[8] = "BC";  rlo[8] = 80;  rw[8] = 16;  rn[9] = "DE";  rlo[9] = 96;  rw[9] = 16;
	rn[10] = "HL"; rlo[10] = 112; rw[10] = 16; rn[11] = "IX"; rlo[11] = 128; rw[11] = 16;
	rn[12] = "BC'"; rlo[12] = 144; rw[12] = 16; rn[13] = "DE'"; rlo[13] = 160; rw[13] = 16;
	rn[14] = "HL'"; rlo[14] = 176; rw[14] = 16; rn[15] = "IY"; rlo[15] = 192; rw[15] = 16;
	rn[16] = "IM"; rlo[16] = 208; rw[16] = 2;  rn[17] = "IFF1"; rlo[17] = 210; rw[17] = 1;
	rn[18] = "IFF2"; rlo[18] = 211; rw[18] = 1; rn[19] = "F-XY"; rlo[19] = 8; rw[19] = 8;
	for (i = 0; i < NR; i = i + 1) rdiff[i] = 0;
end
function [15:0] fld(input [211:0] r, input integer lo, input integer w);
	integer k;
	begin fld = 0; for (k = 0; k < w; k = k + 1) fld[k] = r[lo + k]; end
endfunction

// the snapshots: one queue per core (they may take them at different clocks)
localparam integer QN = 64;
reg [211:0] q_s [0:QN - 1];
reg [211:0] q_t [0:QN - 1];
reg [63:0] q_op [0:QN - 1];
integer nq_s = 0, nq_t = 0, ncmp = 0, rerr = 0, rshown = 0, j;
reg m1r_s = 1'b0, m1r_t = 1'b0, rfr_s = 1'b0, rfr_t = 1'b0;
reg [211:0] a_r, b_r;
reg [8*80-1:0] what;
always @(negedge clk) begin
	if (rfr_s && !rfsh_s && check_at(opn_s - 1)) begin q_s[nq_s % QN] = reg_s; q_op[nq_s % QN] = {hist[7], hist[6], hist[5], hist[4], hist[3], hist[2], hist[1], hist[0]}; nq_s = nq_s + 1; end
	rfr_s = rfsh_s;
	if (rfr_t && !rfsh_t && check_at(opn_t - 1)) begin q_t[nq_t % QN] = reg_t; nq_t = nq_t + 1; end
	rfr_t = rfsh_t;
	m1r_s = m1_s; m1r_t = m1_t;
	while (ncmp < nq_s && ncmp < nq_t) begin
		a_r = q_s[ncmp % QN]; b_r = q_t[ncmp % QN];
		if (1) begin
			what = "";
			for (j = 0; j < NR - 1; j = j + 1)
				if (j != 7 && j != 5 && (j != 1 || REGF)) begin        // PC: the bus shows it; R: below
					if (fld(a_r, rlo[j], rw[j]) != fld(b_r, rlo[j], rw[j])) begin
						rdiff[j] = rdiff[j] + 1;
						what = {what, " ", rn[j]};
					end
				end
			// F without X / Y (bits 3, 5: undocumented)
			if ((fld(a_r, 8, 8) & 16'hD7) != (fld(b_r, 8, 8) & 16'hD7)) begin rdiff[19] = rdiff[19] + 1; what = {what, " F-XY"}; end
			// R: not here (the silicon core counts it at another clock of M1); the bus checks it at the refresh
			if (what != "") begin
				rerr = rerr + 1;
				if (rshown < MAXSHOW) begin
					rshown = rshown + 1;
					$display("tb_z80s_t80: check %0d (M1 %0d), the opcodes before: %h %h %h %h %h %h %h %h:%0s", ncmp,
						NPRE + PERIOD * (ncmp + 1) + PERIOD - 1, q_op[ncmp % QN][63:56], q_op[ncmp % QN][55:48],
						q_op[ncmp % QN][47:40], q_op[ncmp % QN][39:32], q_op[ncmp % QN][31:24], q_op[ncmp % QN][23:16],
						q_op[ncmp % QN][15:8], q_op[ncmp % QN][7:0], what);
					if (ncmp > 0) begin
						a_r = q_s[(ncmp - 1) % QN]; b_r = q_t[(ncmp - 1) % QN];
						$display("tb_z80s_t80:    before: A %h F %h BC %h DE %h HL %h IX %h IY %h SP %h (both)",
							a_r[7:0], a_r[15:8], a_r[95:80], a_r[111:96], a_r[127:112], a_r[143:128], a_r[207:192], a_r[63:48]);
						a_r = q_s[ncmp % QN]; b_r = q_t[ncmp % QN];
					end
					$display("tb_z80s_t80:    sil A %h F %h BC %h DE %h HL %h IX %h IY %h SP %h AF' %h%h BC' %h DE' %h HL' %h I %h R %h IM %0d IFF %b%b",
						a_r[7:0], a_r[15:8], a_r[95:80], a_r[111:96], a_r[127:112], a_r[143:128], a_r[207:192], a_r[63:48],
						a_r[23:16], a_r[31:24], a_r[159:144], a_r[175:160], a_r[191:176], a_r[39:32], a_r[47:40], a_r[209:208], a_r[211], a_r[210]);
					$display("tb_z80s_t80:    t80 A %h F %h BC %h DE %h HL %h IX %h IY %h SP %h AF' %h%h BC' %h DE' %h HL' %h I %h R %h IM %0d IFF %b%b",
						b_r[7:0], b_r[15:8], b_r[95:80], b_r[111:96], b_r[127:112], b_r[143:128], b_r[207:192], b_r[63:48],
						b_r[23:16], b_r[31:24], b_r[159:144], b_r[175:160], b_r[191:176], b_r[39:32], b_r[47:40], b_r[209:208], b_r[211], b_r[210]);
				end
				if (STOP_REG) begin report; $finish; end
			end
		end
		ncmp = ncmp + 1;
	end
end

localparam integer NS = 11;
integer diff [0:NS - 1];
integer errors = 0, shown = 0, m1s = 0, ios = 0, ints = 0, wrs = 0, diverged = 0, clocks = 0;
reg m1_q = 1'b0, iorq_q = 1'b0, wr_q = 1'b0;
// IORQ of the first M1 after power on: T80pa only (IntCycleD_n starts at 0), not compared
wire [NS - 1:0] dv = {a_s != a_t, (wr_s && wr_t && do_s != do_t), mreq_s != mreq_t, (iorq_s != iorq_t) && opn_t > 0,
	rd_s != rd_t, wr_s != wr_t, m1_s != m1_t, rfsh_s != rfsh_t, halt_s != halt_t, busack_s != busack_t,
	(rfsh_s && rfsh_t && a_s[6:0] != a_t[6:0])};
reg [8*8-1:0] nm [0:NS - 1];
initial begin
	nm[10] = "A"; nm[9] = "DO"; nm[8] = "MREQ"; nm[7] = "IORQ"; nm[6] = "RD"; nm[5] = "WR"; nm[4] = "M1";
	nm[3] = "RFSH"; nm[2] = "HALT"; nm[1] = "BUSACK"; nm[0] = "R";
	for (i = 0; i < NS; i = i + 1) diff[i] = 0;
	for (i = 0; i < 8; i = i + 1) hist[i] = 8'h00;
end

task report;
	begin
		$display("tb_z80s_t80: pattern %0d out0 %0d: %0d Z80 cycles (%0d clocks), %0d M1, %0d writes, %0d I/O (%0d INT ack)%s",
			PATTERN, OUT0, ncyc, clocks, m1s, wrs, ios, ints, diverged ? ", DIVERGED" : "");
		for (i = NS - 1; i >= 0; i = i - 1)
			if (diff[i] != 0) $display("tb_z80s_t80:   %0s differs in %0d clocks", nm[i], diff[i]);
		$display("tb_z80s_t80: %0d M1 compared, %0d with a register difference", ncmp, rerr);
		for (i = 0; i < NR; i = i + 1)
			if (rdiff[i] != 0) $display("tb_z80s_t80:   %0s differs after %0d M1", rn[i], rdiff[i]);
		$display("tb_z80s_t80: %0d errors", errors);
	end
endtask

always @(negedge clk) if (ncyc >= TRACE_FROM && ncyc <= TRACE_TO)
	$display("tb_z80s_t80: trace %0d %s int %b nmi %b: sil A %h DI %h DO %h mreq %b iorq %b rd %b wr %b m1 %b rfsh %b | t80 A %h DI %h DO %h mreq %b iorq %b rd %b wr %b m1 %b rfsh %b",
		ncyc, cen_p ? "p" : cen_n ? "n" : "-", p_int, nmi, a_s, di_s, do_s, mreq_s, iorq_s, rd_s, wr_s, m1_s, rfsh_s,
		a_t, di_t, do_t, mreq_t, iorq_t, rd_t, wr_t, m1_t, rfsh_t);
always @(negedge clk) if (!reset) begin
	clocks = clocks + 1;
	if (dv != 0) begin
		errors = errors + 1;
		for (i = 0; i < NS; i = i + 1) if (dv[i]) diff[i] = diff[i] + 1;
		if (shown < MAXSHOW) begin
			shown = shown + 1;
			$display("tb_z80s_t80: cycle %0d %s: sil A %h DO %h mreq %b iorq %b rd %b wr %b m1 %b rfsh %b halt %b | t80 A %h DO %h mreq %b iorq %b rd %b wr %b m1 %b rfsh %b halt %b | ops %h %h %h %h %h %h",
				ncyc, cen_p ? "p" : cen_n ? "n" : "-", a_s, do_s, mreq_s, iorq_s, rd_s, wr_s, m1_s, rfsh_s, halt_s,
				a_t, do_t, mreq_t, iorq_t, rd_t, wr_t, m1_t, rfsh_t, halt_t,
				hist[5], hist[4], hist[3], hist[2], hist[1], hist[0]);
		end
		if ((dv[10] && !(rfsh_s || rfsh_t) && (mreq_s || iorq_s || mreq_t || iorq_t)) || dv[9]) begin
			if (!diverged) $display("tb_z80s_t80: DIVERGED at cycle %0d (address or data)", ncyc);
			diverged = 1;
			if (STOP_ON) begin report; $finish; end
		end
	end
	if (m1_s && !m1_q) m1s = m1s + 1;
	if (iorq_s && !iorq_q) begin ios = ios + 1; if (m1_s) ints = ints + 1; end
	if (wr_s && !wr_q) wrs = wrs + 1;
	m1_q = m1_s; iorq_q = iorq_s; wr_q = wr_s;
	if (ncyc >= CYCLES) begin report; $finish; end
end
endmodule
