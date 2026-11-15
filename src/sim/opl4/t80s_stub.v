`timescale 1ns / 1ps
// t80s for tb_opl4 (iverilog, the T80 is VHDL): an idle GS cpu, gs_top only gives its SDRAM port 2
module t80s #(parameter Mode = 0, parameter T2Write = 0, parameter IOWait = 1) (
	input wire RESET_n, input wire CLK, input wire CEN, input wire WAIT_n, input wire INT_n,
	input wire NMI_n, input wire BUSRQ_n,
	output wire M1_n, output wire MREQ_n, output wire IORQ_n, output wire RD_n, output wire WR_n,
	output wire RFSH_n, output wire HALT_n, output wire BUSAK_n,
	output wire [15:0] A, input wire [7:0] DI, output wire [7:0] DO
);
assign {M1_n, MREQ_n, IORQ_n, RD_n, WR_n, RFSH_n, HALT_n, BUSAK_n} = 8'hFF;
assign A = 16'h0000;
assign DO = 8'hFF;
endmodule
