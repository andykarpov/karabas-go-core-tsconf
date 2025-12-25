module dc_filter(
	input wire clk,
	input wire audio_en,
	input wire [WIDTH-1:0] sample,
	output reg [WIDTH-1:0] filtered
);

parameter SIZE = 256;
parameter WIDTH = 8;
localparam IDXWIDTH = 10; // $clog2(SIZE)

reg [WIDTH-1:0] buffer [0:SIZE-1];
reg [IDXWIDTH-1:0] idx;
reg signed [WIDTH+IDXWIDTH-1:0] dc_sum;

function signed [WIDTH-1:0] dc(input signed [WIDTH-1:0] sample);
begin
	dc_sum <= dc_sum - buffer[idx];
	buffer[idx]  <= sample;
	dc_sum <= dc_sum + sample;
	idx <= (idx + 1) % SIZE;
	dc <= dc_sum / SIZE;
end
endfunction

always @(posedge clk) begin
	if (audio_en)
		filtered <= sample - dc(sample);
end
	
endmodule
	