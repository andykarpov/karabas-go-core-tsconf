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

// write strobe
reg prev_wr_n = 1;
reg opl2_wr = 0;
always @(posedge clk or posedge reset) begin
	if (reset) begin
		prev_wr_n <= 1;
		opl2_wr <= 0;
	end
	else begin
		prev_wr_n <= wr_n || cs_n;
		opl2_wr <= 0;
		if (~cs_n && ~wr_n && prev_wr_n) begin
			opl2_wr <= 1;
		end
	end
end

jtopl #(.OPL_TYPE(2)) jtopl_inst(
	 .rst(reset),
    .clk(clk),
    .cen(clk_en),
    .din(din),
    .addr(a),
    .cs_n(1'b0),
    .wr_n(~opl2_wr),
    .dout(dout),
    .irq_n(),
	 .snd(snd),
    .sample()
);

assign out_l = snd;
assign out_r = snd;

endmodule

