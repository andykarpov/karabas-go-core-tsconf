module compressor(
	input wire clk,
	input wire [15:0] signal_in,
	output reg [15:0] signal_out
);

localparam [3:0] comp_f = 4;
localparam [3:0] comp_a = 2;
localparam       comp_x = ((32767 * (comp_f - 1)) / ((comp_f * comp_a) - 1)) + 1; // +1 to make sure it won't overflow
localparam       comp_b = comp_x * comp_a;

function [15:0] compr; input [15:0] inp;
	reg [15:0] v, v2;
	begin
		v  = inp[15] ? (~inp) + 1'd1 : inp;
		v2 = (v < comp_x[15:0]) ? (v * comp_a) : (((v - comp_x[15:0])/comp_f) + comp_b[15:0]);
		compr = inp[15] ? ~(v2-1'd1) : v2;
	end
endfunction

always @(posedge clk) begin
	signal_out <= compr(signal_in);
end

endmodule