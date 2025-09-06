/*-------------------------------------------------------------------------------------------------------------------
-- Audio samplerate generator and restrober between 28MHz clock domain and HDMI clock domain (24...80MHz)
-- 
-- @author TSLabs
-- (c) 2025
---------------------------------------------------------------------------------------------------------------------*/
module audio_restrober(
	input wire 				clk, 		// input hdmi pixelclock (mux from FT 24...80 MHz or 28 MHz system clock)
	input wire 				clk_ref, // 28 MHz reference clock
	input wire 				reset, 
	input wire [15:0] 	audio_l, // input audio from 28 MHz clock domain
	input wire [15:0] 	audio_r,
	output wire [15:0] 	out_l, 	// output audio for hdmi clock domain
	output wire [15:0] 	out_r,
	output wire 			out_clk 	// output audio strobe at desired samplerate (in hdmi clock domain)
);

// audio samplerate
parameter SAMPLERATE = 192000;
parameter CLKRATE 	= 28000000;

// audio strobe generator
wire audio_stb;
audio_samplerate #(.SAMPLERATE(SAMPLERATE), .CLKRATE(CLKRATE)) audio_samplerate(
	.clk				(clk_ref),
	.reset			(reset),
	.audio_stb		(audio_stb)
);

/*
clk_ref:    ___|‾‾‾|___|‾‾‾|___|‾‾‾|___|‾‾‾|___|‾‾‾|___|‾‾‾|___|‾‾‾|___|‾‾‾|___|‾‾‾|___
audio_stb:  ___|‾‾‾‾‾‾‾‾|____________________________________________________________ (1x clock cycle)
stb_reg:    ___|‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾‾|_____________________________________________________ (2x clock cycles)

audio_l,r:    ===A0===A1===A2============================   (sample changes)
audio_in_reg:     A0    A1    A2                            (latched)

stb_reg:       11 -> 10 -> 00 -> ....                   
               ↑ 2 cycles wide pulse in clk_ref domain

clk:      _|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_|‾|_
stb_out_reg:     000111110000... (3-bit shift register)
                 -----
                 detects "10" falling edge here

audio_out_reg:         A0         A1         A2
                       ^ latched at falling edge detect
*/

// new extended srtobe, to be sampled at 24..80 FT clock
reg [1:0] stb_reg;
reg [31:0] audio_in_reg;
always @(posedge clk_ref) begin
  if (audio_stb)
  begin
    audio_in_reg <= {audio_l, audio_r};
    stb_reg <= 2'b11;
  end
  else
    stb_reg <= {stb_reg[0], 1'b0};
end

// restrobe into a new clk domain
reg [2:0] stb_out_reg;
reg [31:0] audio_out_reg;
reg audio_out_clk, audio_out_clk2;
always @(posedge clk)
begin
  stb_out_reg <= {stb_out_reg[1:0], stb_reg[1]};   // re-strobe

  audio_out_clk <= 0;
  if (stb_out_reg[2:1] == 2'b10) begin // falling edge
    audio_out_reg <= audio_in_reg;
	 audio_out_clk <= 1;
  end 
  audio_out_clk2 <= audio_out_clk; // delayed strobe
end

assign {out_l, out_r} = audio_out_reg;
assign out_clk = audio_out_clk2;

endmodule
