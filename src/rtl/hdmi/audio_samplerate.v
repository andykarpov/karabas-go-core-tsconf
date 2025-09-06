module audio_samplerate(
	input wire clk,
	input wire reset,
	output wire audio_stb
);

parameter SAMPLERATE = 192000;
parameter CLKRATE = 28000000;
localparam prescaler = (CLKRATE / SAMPLERATE);

// audio samplerate
reg stb;
reg [9:0] cnt_audio;
always @(posedge clk, posedge reset)
begin
		stb <= 0;
		if (reset) 
			cnt_audio <= 0;
		else 
		begin
			if (cnt_audio > prescaler) 
			begin
				cnt_audio <= 0;
				stb <= 1;
			end
			else
				cnt_audio <= cnt_audio + 1;
		end
end

assign audio_stb = stb;

endmodule
