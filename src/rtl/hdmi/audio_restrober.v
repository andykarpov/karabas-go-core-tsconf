module audio_restrober #(
	parameter 				AUDIO_DW = 16
)
(
	input wire 				clk, 		// input hdmi pixelclock (mux from FT 24...80 MHz or 28 MHz system clock)
	input wire 				clk_ref, // 28 MHz reference clock
	input wire 				reset, 
	input wire           enable,
	input wire           audio_sample, // sampled by hdmi module (clk domain)
	input wire [AUDIO_DW-1:0] 	audio_l, // input audio from 28 MHz clock domain
	input wire [AUDIO_DW-1:0] 	audio_r,
	output wire [AUDIO_DW-1:0] 	out_l, 	// output audio for hdmi clock domain
	output wire [AUDIO_DW-1:0] 	out_r
);

// extended strobe 2 clk clock cycles width
reg [1:0] stb_reg;
always @(posedge clk) begin
  if (reset)
	 stb_reg <= 2'b00;
  else if (audio_sample)
    stb_reg <= 2'b11;
  else
    stb_reg <= {stb_reg[0], 1'b0};
end

// tranfer strobe from clk to clk_ref domain, acquire audio in data reg
reg [2:0] stb_in_reg;
reg [AUDIO_DW*2-1:0] audio_in_reg;
always @(posedge clk_ref) begin
  stb_in_reg <= {stb_in_reg[1:0], stb_reg[1]};   // re-strobe
  if (stb_in_reg[2:1] == 2'b10) // falling edge
	 audio_in_reg <= {audio_l, audio_r};
end

// transfer audio in reg into audio out reg
reg [AUDIO_DW*2-1:0] audio_out_reg;
always @(posedge clk) begin
	if (audio_sample)
		audio_out_reg <= audio_in_reg;
end

// mux output
assign {out_l, out_r} = (enable) ? audio_out_reg : {audio_l, audio_r};

endmodule
