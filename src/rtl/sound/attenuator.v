module attenuator(
	input wire clk,
	input wire [7:0] signal_in,
	input wire [5:0] att,
	output wire [7:0] att_out
);
   
reg     [13:0]         dout;

always @(posedge clk) begin
   dout = signal_in * att;
end

assign   att_out[7:0] = dout[13:6];

endmodule