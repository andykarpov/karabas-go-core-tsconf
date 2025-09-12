module audio_restrober(
	input wire 				clk, 		// input hdmi pixelclock (mux from FT 24...80 MHz or 28 MHz system clock)
	input wire 				clk_ref, // 28 MHz reference clock
	input wire 				reset, 
	input wire           audio_sample, // sampled by hdmi module (clk domain)
	input wire [15:0] 	audio_l, // input audio from 28 MHz clock domain
	input wire [15:0] 	audio_r,
	output wire [15:0] 	out_l, 	// output audio for hdmi clock domain
	output wire [15:0] 	out_r
);

// extended strobe 2 clock cycles width
reg [1:0] stb_reg;
always @(posedge clk) begin
  if (audio_sample)
  begin
    stb_reg <= 2'b11;
  end
  else
    stb_reg <= {stb_reg[0], 1'b0};
end

// tranfer strobe from clk to clk_ref domain, acquire audio in data reg
reg [2:0] stb_out_reg;
reg [31:0] audio_in_reg;
always @(posedge clk_ref)
begin
  stb_out_reg <= {stb_out_reg[1:0], stb_reg[1]};   // re-strobe
  if (stb_out_reg[2:1] == 2'b10) begin // falling edge
	 audio_in_reg <= {audio_l, audio_r};
  end
end

// transfer audio in reg into audio out reg
reg [31:0] audio_out_reg;
always @(posedge clk)
begin
	if (audio_sample) begin
		audio_out_reg <= audio_in_reg;
	end
end

assign {out_l, out_r} = audio_out_reg;

endmodule
