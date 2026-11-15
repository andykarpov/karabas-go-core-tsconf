`timescale 1ns / 1ps
// z80s_t80pa: z80-silicon (z80_silicon_cen.v, the NMOS Z80 from its transistor netlist) with the ports of
// T80pa as tsconf.v uses them: one clock with the enables CEN_p (the rising edge of the Z80 clock, zpos)
// and CEN_n (the falling one, zneg), the control signals active low. The bus timing is that of T80pa
// (src/sim/run_z80s_sim.sh: tb_z80s_t80); the differences are those of T80pa against the chip, listed
// there. NMOS: OUT (C),0 (T80pa had OUT0 = 1, OUT (C),255).
module z80s_t80pa (
	input  wire        RESET_n,
	input  wire        CLK,
	input  wire        CEN_p,
	input  wire        CEN_n,
	input  wire        WAIT_n,
	input  wire        INT_n,
	input  wire        NMI_n,
	input  wire        BUSRQ_n,
	output wire        M1_n,
	output wire        MREQ_n,
	output wire        IORQ_n,
	output wire        RD_n,
	output wire        WR_n,
	output wire        RFSH_n,
	output wire        HALT_n,
	output wire        BUSAK_n,
	output wire [15:0] A,
	input  wire [7:0]  DI,
	output wire [7:0]  DO
);

wire mreq, iorq, rd, wr, rfsh, m1, halt, busack;

z80s_Z80 cpu (
	.clk(CLK), .cen_p(CEN_p), .cen_n(CEN_n),
	.data_in(DI), .data_out(DO), .adr(A),
	.mreq(mreq), .iorq(iorq), .rd(rd), .wr(wr),
	.data_z(), .adr_z(), .controls_z(),
	.rfsh(rfsh), .p_m1(m1), .halt(halt),
	.p_wait(~WAIT_n), .p_int(~INT_n), .nmi(~NMI_n), .reset(~RESET_n),
	.busrq(~BUSRQ_n), .busack(busack)
);

assign M1_n    = ~m1;
assign MREQ_n  = ~mreq;
assign IORQ_n  = ~iorq;
assign RD_n    = ~rd;
assign WR_n    = ~wr;
assign RFSH_n  = ~rfsh;
assign HALT_n  = ~halt;
assign BUSAK_n = ~busack;

endmodule
