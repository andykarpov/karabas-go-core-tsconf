module pll_reset (
	input wire clk,
	input wire i_reset,
	output wire o_reset
);

reg [7:0] pll_rst_cnt = 8'd0;
always @(posedge clk)
begin
	if (i_reset) begin
		pll_rst_cnt <= 8'b10000000;
	end
	if (pll_rst_cnt > 0) pll_rst_cnt <= pll_rst_cnt+1;
end

assign o_reset = pll_rst_cnt[7];

endmodule
