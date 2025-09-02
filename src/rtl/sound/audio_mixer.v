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
	
	input wire [7:0] saa_l,
	input wire [7:0] saa_r,
	
	input wire [14:0] gs_l,
	input wire [14:0] gs_r,
	
	input wire [15:0] fm_l,
	input wire [15:0] fm_r,

`ifdef HW_ID2
	input wire [15:0] adc_l,
	input wire [15:0] adc_r,
`endif
	
	input wire fm_ena,
	
	output wire [15:0] audio_l,
	output wire [15:0] audio_r
);

reg  [8:0] sum_ch_a,sum_ch_b,sum_ch_c;
reg  [7:0] psg_a,psg_b,psg_c;
reg [11:0] psg_l,psg_r,opn_s;
reg [11:0] tsfm_l, tsfm_r;
reg [11:0] covox_l, covox_r;

always @(posedge clk) begin

	sum_ch_a <= { 1'b0, ssg1_a } + { 1'b0, ssg0_a };
	sum_ch_b <= { 1'b0, ssg1_b } + { 1'b0, ssg0_b };
	sum_ch_c <= { 1'b0, ssg1_c } + { 1'b0, ssg0_c };

	psg_a <= sum_ch_a[8] ? 8'hFF : sum_ch_a[7:0];
	psg_b <= sum_ch_b[8] ? 8'hFF : sum_ch_b[7:0];
	psg_c <= sum_ch_c[8] ? 8'hFF : sum_ch_c[7:0];

	psg_l <= (mode == 2'b00 || mode== 2'b10) ? {3'b000, psg_a, 1'd0} + {4'b0000, psg_b} : {3'b000, psg_a, 1'd0} + {4'b0000, psg_c};
	psg_r <= (mode == 2'b00 || mode== 2'b10) ? {3'b000, psg_c, 1'd0} + {4'b0000, psg_b} : {3'b000, psg_b, 1'd0} + {4'b0000, psg_c};
	opn_s <= {{2{fm_l[15]}}, fm_l[15:6]} + {{2{fm_r[15]}}, fm_r[15:6]};

	tsfm_l <= fm_ena ? $signed(opn_s) + $signed(psg_l) : $signed(psg_l);
	tsfm_r <= fm_ena ? $signed(opn_s) + $signed(psg_r) : $signed(psg_r);
	
	covox_l <= $signed({3'b000, covox_a, 1'b0} + {3'b000, covox_b, 1'b0} + {4'b0000, covox_fb});
	covox_r <= $signed({3'b000, covox_c, 1'b0} + {3'b000, covox_d, 1'b0} + {4'b0000, covox_fb});
end

`ifdef HW_ID2
wire [11:0] mix_l = tsfm_l + $signed({1'b0, gs_l[14:4]}) + {adc_l[15], adc_l[15:5]} + covox_l + $signed({2'b00, saa_l, 2'b000}) + $signed({4'b0000, speaker, 7'b0000000});
wire [11:0] mix_r = tsfm_r + $signed({1'b0, gs_r[14:4]}) + {adc_r[15], adc_r[15:5]} + covox_r + $signed({2'b00, saa_r, 2'b000}) + $signed({4'b0000, speaker, 7'b0000000});
`else
wire [11:0] mix_l = tsfm_l + $signed({1'b0, gs_l[14:4]}) + covox_l + $signed({2'b00, saa_l, 2'b000}) + $signed({4'b0000, speaker, 7'b0000000});
wire [11:0] mix_r = tsfm_r + $signed({1'b0, gs_r[14:4]}) + covox_r + $signed({2'b00, saa_r, 2'b000}) + $signed({4'b0000, speaker, 7'b0000000});
`endif

compressor compressor (.clk(clk), .in1(mix_l), .in2(mix_r), .out1(audio_l), .out2(audio_r));

endmodule
