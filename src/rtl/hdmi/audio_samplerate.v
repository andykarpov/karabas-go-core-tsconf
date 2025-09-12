module audio_samplerate(
	input wire clk,
	input wire reset,
	output wire audio_stb
);

parameter SAMPLERATE = 44100;
parameter CLKRATE = 28000000;
localparam prescaler = (CLKRATE / SAMPLERATE);

// audio samplerate
reg clk_audio;
reg [9:0] cnt_audio;
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
	if (~prev_clk_audio && clk_audio) begin
		stb <= 1;
	end
	prev_clk_audio <= clk_audio;
end

assign audio_stb = stb;

endmodule