module opl2_top(
	 input wire reset,
    input wire clk,
    input wire wr_n,
	 input wire cs_n,
    input wire [7:0] din,
    input wire a,
	 output wire [7:0] dout,
    output wire signed [15:0] out_l,
    output wire signed [15:0] out_r
);

wire clk_en;
opl2_clk opl2_clk_inst(
		.clk(clk),
		.reset(reset),
		.clk_en(clk_en)
);

wire [15:0] snd;

jtopl #(.OPL_TYPE(2)) jtopl_inst(
	 .rst(reset),
    .clk(clk),
    .cen(clk_en),
    .din(din),
    .addr(a),
    .cs_n(cs_n),
    .wr_n(wr_n),
    .dout(dout),
    .irq_n(),
	 .snd(snd),
    .sample()
);

assign out_l = snd;
assign out_r = snd;

endmodule

