module audio_samplerate(
	input wire clk,
	input wire reset,
	input wire [7:0] freq,
	output wire audio_stb
);

parameter SAMPLERATE = 44100;

reg [10:0] prescaler;
always @(posedge clk)
	prescaler <= (freq * 1000000) / SAMPLERATE;

// audio samplerate
reg clk_audio;
reg [10:0] cnt_audio;
always @(posedge clk, posedge reset)
begin
		if (reset) 
		begin
			cnt_audio <= 0;
			clk_audio <= 0;
		end
		else 
		begin
			if (cnt_audio > prescaler) 
			begin
				cnt_audio <= 0;
				clk_audio <= ~clk_audio;
			end
			else
				cnt_audio <= cnt_audio + 1;
		end
end

reg stb;
reg prev_clk_audio;
always @(posedge clk)
begin
	stb <= 0;
	if (~prev_clk_audio && clk_audio) 
		stb <= 1'b1;
	prev_clk_audio <= clk_audio;
end

assign audio_stb = stb;

endmodule