`timescale 1ns / 1ps
`default_nettype none

/*
 The clock enables of clk_sys that follow clk_bus. Both come from the PLL with phase 0 and clk_bus = clk_sys / 3,
 so every edge of clk_bus is an edge of clk_sys.
 - ce: high in the clk_sys period that ends with an edge of clk_bus (the SRAM controller starts its cycle with
   it). bus_tgl changes at an edge of clk_bus, tgl_s[0] takes it at the next edge of clk_sys, ce is high in the
   third: the paths are timed as paths between the two clocks (11.9 ns), not synchronised.
 - v_clk: ce made on the falling clk_sys, high from 6 ns before to 6 ns after the edge of clk_bus (the V_CLK pin of
   the Go, the clock of the video DAC: the old ce_28m of the tops, which counted clk_sys from power-up).
*/

module bus_ce (
	input wire clk_sys,
	input wire clk_bus,
	output reg ce = 1'b0,
	output reg v_clk = 1'b0
);

reg bus_tgl = 1'b0;
always @(posedge clk_bus)
	bus_tgl <= ~bus_tgl;

reg [1:0] tgl_s = 2'b00;
always @(posedge clk_sys) begin
	tgl_s <= {tgl_s[0], bus_tgl};
	ce <= tgl_s[0] ^ tgl_s[1];
end

always @(negedge clk_sys)
	v_clk <= ce;

endmodule
