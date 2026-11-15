module audio_mixer (
	input wire clk,
	
	input wire mute,
	input wire [1:0] mode,
	
	input wire speaker,
	input wire tape_in,
	
	input wire [7:0] ssg0_a,
	input wire [7:0] ssg0_b,
	input wire [7:0] ssg0_c,
	
	input wire [7:0] ssg1_a,
	input wire [7:0] ssg1_b,
	input wire [7:0] ssg1_c,
	
	input wire [7:0] covox_a,
	input wire [7:0] covox_b,
	input wire [7:0] covox_c,
	input wire [7:0] covox_d,
	input wire [7:0] covox_fb,	
	
	// the GS + the OPL4 at half, interpolated and filtered (audio_lpf.v), signed
	input wire [16:0] gs_opl4_l,
	input wire [16:0] gs_opl4_r,
	
`ifdef HW_ID2
	input wire [15:0] adc_l,
	input wire [15:0] adc_r,
`endif

`ifdef HW_ID3
    input wire [15:0] esp_l,
	 input wire [15:0] esp_r,
`endif
	
	output reg signed [15:0] audio_l = 16'sd0,
	output reg signed [15:0] audio_r = 16'sd0
);

reg signed [11:0] psg_l, psg_r;
reg signed [11:0] covox_l, covox_r;

always @(posedge clk) begin

	psg_l <= (mode == 2'b00 || mode== 2'b10) ? 
		$signed({3'b000, ssg0_a, 1'd0}) + $signed({3'b000, ssg1_a, 1'd0}) + $signed({4'b0000, ssg0_b}) + $signed({4'b0000, ssg1_b}) : 
		$signed({3'b000, ssg0_a, 1'd0}) + $signed({3'b000, ssg1_a, 1'd0}) + $signed({4'b0000, ssg0_c}) + $signed({4'b0000, ssg1_c});
	psg_r <= (mode == 2'b00 || mode== 2'b10) ? 
		$signed({3'b000, ssg0_c, 1'd0}) + $signed({3'b000, ssg1_c, 1'd0}) + $signed({4'b0000, ssg0_b}) + $signed({4'b0000, ssg1_b}) : 
		$signed({3'b000, ssg0_b, 1'd0}) + $signed({3'b000, ssg1_b, 1'd0}) + $signed({4'b0000, ssg0_c}) + $signed({4'b0000, ssg1_c});	
	covox_l <= $signed({2'b00, covox_a, 2'b00}) + $signed({2'b00, covox_b, 2'b00}) + $signed({3'b000, covox_fb, 1'b0});
	covox_r <= $signed({2'b00, covox_c, 2'b00}) + $signed({2'b00, covox_d, 2'b00}) + $signed({3'b000, covox_fb, 1'b0});
end

// the sum in 18 bits, saturated to 16 (it wrapped around before: a click on the loud parts)
wire signed [17:0] mix_l = 	$signed({{2{psg_l[11]}}, psg_l[11:0], 4'b0000}) +
										$signed({gs_opl4_l[16], gs_opl4_l}) +
`ifdef HW_ID2
										$signed({{2{adc_l[15]}}, adc_l[15:0]}) +
`endif
`ifdef HW_ID3
										$signed({{2{esp_l[15]}}, esp_l[15:0]}) +
`endif
										$signed({{2{covox_l[11]}}, covox_l[11:0], 4'b0000}) +
										$signed({4'b0000, speaker, 7'b0000000, 6'b000000});

wire signed [17:0] mix_r = 	$signed({{2{psg_r[11]}}, psg_r[11:0], 4'b0000}) +
										$signed({gs_opl4_r[16], gs_opl4_r}) +
`ifdef HW_ID2
										$signed({{2{adc_r[15]}}, adc_r[15:0]}) +
`endif
`ifdef HW_ID3
										$signed({{2{esp_r[15]}}, esp_r[15:0]}) +
`endif
										$signed({{2{covox_r[11]}}, covox_r[11:0], 4'b0000}) +
										$signed({4'b0000, speaker, 7'b0000000, 6'b000000});

function signed [15:0] sat16;
	input signed [17:0] v;
	begin
		if (v > 18'sd32767)       sat16 = 16'sh7fff;
		else if (v < -18'sd32768) sat16 = 16'sh8000;
		else                      sat16 = v[15:0];
	end
endfunction

// registered: the DACs and the HDMI audio take it on the falling clk
always @(posedge clk) begin
	audio_l <= sat16(mix_l);
	audio_r <= sat16(mix_r);
end

endmodule
