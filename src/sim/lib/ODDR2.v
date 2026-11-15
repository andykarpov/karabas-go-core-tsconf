`timescale 1ns / 1ps
// ODDR2 for iverilog (the parts the core uses: D0 on C0, D1 on C1, no CE / R / S)
module ODDR2 #(parameter DDR_ALIGNMENT = "NONE", parameter INIT = 1'b0, parameter SRTYPE = "SYNC") (
	output reg Q,
	input wire C0, input wire C1, input wire CE, input wire D0, input wire D1, input wire R, input wire S
);
initial Q = INIT;
always @(posedge C0) Q <= D0;
always @(posedge C1) Q <= D1;
endmodule
