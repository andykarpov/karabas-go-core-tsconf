module pll_reset (
	input wire clk,
	input wire i_reset,
	output wire o_reset
);

reg [3:0] pll_rst_cnt = 4'd0;
always @(posedge clk)
begin
	if (i_reset) begin
		pll_rst_cnt <= 4'b1000;
	end
	if (pll_rst_cnt > 0) pll_rst_cnt <= pll_rst_cnt+1;
end

assign o_reset = pll_rst_cnt[3];

endmodule
