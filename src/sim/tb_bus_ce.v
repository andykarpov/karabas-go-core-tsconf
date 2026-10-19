`timescale 1ns / 1ps

// bus_ce (rtl/bus_ce.v) with the PLL of the tops (kg_pll, the unisim PLL_BASE in ISim): clk_bus must rise exactly
// at the clk_sys edges that close a clk_sys period with ce high, and at no other one; v_clk must be high at every
// edge of clk_bus and low at the other edges of clk_sys (the old ce_28m: high from the falling clk_sys before to
// the one after the edge of clk_bus). Ends with "tb_bus_ce: N errors".

module tb_bus_ce;

reg clk50 = 1'b0;
always #10 clk50 = ~clk50;

wire [5:0] pll_clk;
wire locked;
kg_pll #(
	.DIVCLK_DIVIDE(2), .CLKFBOUT_MULT(37),
	.CLKOUT0_DIVIDE(11), .CLKOUT1_DIVIDE(116), .CLKOUT2_DIVIDE(33), .CLKOUT3_DIVIDE(77),
	.BUFG_MASK(6'b001011)
) pll (.clk_in(clk50), .rst(1'b0), .clk_out(pll_clk), .locked(locked));
wire clk_sys = pll_clk[0];
wire clk_bus;
BUFG bufg_clk_bus(.I(pll_clk[2]), .O(clk_bus));

wire ce, v_clk;
bus_ce dut(.clk_sys(clk_sys), .clk_bus(clk_bus), .ce(ce), .v_clk(v_clk));

integer errors = 0, sys_edges = 0, bus_edges = 0;
task automatic fail;
	input [8*40-1:0] what;
	begin
		errors = errors + 1;
		if (errors <= 10) $display("%t ERROR: %0s", $time, what);
	end
endtask

// the time of the last edge of each clock (the BUFG models add no delay: the edges coincide in time)
realtime t_bus = 0.0;
always @(posedge clk_bus) begin
	t_bus = $realtime;
	if (locked && v_clk !== 1'b1) fail("v_clk low at an edge of clk_bus");
end
reg ce_before = 1'b0;
always @(posedge clk_sys) ce_before <= ce;   // the value of ce in the period this edge ends
reg settled = 1'b0;
always @(posedge clk_sys) begin
	#0.1;
	if (locked && settled) begin
		sys_edges = sys_edges + 1;
		if ($realtime - 0.1 - t_bus < 0.01 && $realtime - 0.1 - t_bus > -0.01) begin
			bus_edges = bus_edges + 1;
			if (ce_before !== 1'b1) fail("an edge of clk_bus without ce");
		end
		else begin
			if (ce_before !== 1'b0) fail("ce without an edge of clk_bus");
			if (v_clk !== 1'b0) fail("v_clk high at another edge of clk_sys");
		end
	end
end

initial begin
	@(posedge locked);
	repeat (20) @(posedge clk_bus);
	settled = 1'b1;
	repeat (100000) @(posedge clk_sys);
	$display("tb_bus_ce: %0d edges of clk_sys, %0d of them with clk_bus", sys_edges, bus_edges);
	if (bus_edges * 3 < sys_edges - 3 || bus_edges * 3 > sys_edges + 3) fail("clk_bus is not clk_sys / 3");
	$display("tb_bus_ce: %0d errors", errors);
	$finish;
end

endmodule
