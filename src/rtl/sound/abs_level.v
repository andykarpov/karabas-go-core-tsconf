module abs_level (
	input wire clk,
	input wire signed [15:0] audio_sample,
	output reg [15:0] audio_abs
);

// absolute value 0..65535
always @(posedge clk) begin
	if (audio_sample < 0)
		audio_abs <= -audio_sample;
	else 
		audio_abs <= audio_sample;
end

endmodule
