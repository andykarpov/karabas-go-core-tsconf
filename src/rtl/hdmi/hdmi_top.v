`timescale 1ns / 1ps
`default_nettype none

module hdmi_top(

	input wire clk,
	input wire clk_ref,
	input wire clk_8,

	input wire reset,
	
	input wire [23:0] vga_rgb,
	input wire vga_hs,
	input wire vga_vs,
	input wire vga_de,
	
	input wire [23:0] ft_rgb,
	input wire ft_hs,
	input wire ft_vs,
	input wire ft_de,
	
	input wire ft_sel,
	
	input wire [15:0] audio_l,
	input wire [15:0] audio_r,
	
	output wire [3:0] tmds_p,
	output wire [3:0] tmds_n,
	
	output wire [7:0] freq
);

parameter SAMPLERATE = 44100;

// clocks
wire clk_hdmi, clk_hdmi_n;
wire p_clk_int, p_clk_div2;
wire [7:0] hdmi_freq;
wire lockedx5;
wire pll_reset;

hdmi_pll hdmi_pll (
	.clk(clk),
	.clk_ref(clk_ref),
	.clk_8(clk_8),
	.reset(reset),
	.vdac2_sel(ft_sel),
	.clk_hdmi(clk_hdmi),
	.clk_hdmi_n(clk_hdmi_n),
	.clk_pix(p_clk_int),
	.clk_pix2(p_clk_div2),
	.freq(hdmi_freq),
	.locked(lockedx5),
	.o_reset(pll_reset)
);
assign freq = hdmi_freq;

// mux signals
wire [7:0] host_vga_r, host_vga_g, host_vga_b;
wire host_vga_hs, host_vga_vs, host_vga_blank;

// metastabilize video data
wire [26:0] ft_data, vga_data;
reg [53:0] ft_data_r;
always @(negedge clk) begin
	ft_data_r[26:0] <= {ft_de, ft_hs, ft_vs, ft_rgb[23:0]};
	ft_data_r[53:27] <= ft_data_r[26:0];
end
reg [53:0] ft_data_r2;
reg [53:0] vga_data_r2;
always @(posedge p_clk_int) begin
	ft_data_r2[26:0] <= ft_data_r[53:27];
	ft_data_r2[53:27] <= ft_data_r2[26:0];
	vga_data_r2[26:0] <= {vga_de, vga_hs, vga_vs, vga_rgb[23:0]};
	vga_data_r2[53:27] <= vga_data_r2[26:0];
end
assign ft_data = ft_data_r2[53:27];
assign vga_data = vga_data_r2[53:27];

assign host_vga_r = (ft_sel ? (~ft_data[26] ? 8'b0 : ft_data[23:16]) : (~vga_data[26] ? 8'b0 : vga_data[23:16]));
assign host_vga_g = (ft_sel ? (~ft_data[26] ? 8'b0 : ft_data[16:8]) : (~vga_data[26] ? 8'b0 : vga_data[15:8]));
assign host_vga_b = (ft_sel ? (~ft_data[26] ? 8'b0 : ft_data[7:0]) : (~vga_data[26] ? 8'b0 : vga_data[7:0]));
assign host_vga_hs = (ft_sel ? ft_data[25] : vga_data[25]);
assign host_vga_vs = (ft_sel ? ft_data[24] : vga_data[24]);
assign host_vga_blank = (ft_sel ? ~ft_data[26] : ~vga_data[26]);

// metastabilize audio data for FT
wire [15:0] audio_out_l, audio_out_r;
audio_restrober audio_restrober(
	.clk(p_clk_int),
	.clk_ref(clk_ref),
	.reset(reset || ~lockedx5),
	.audio_sample(audio_sample),
	.enable(1'b1),
	.audio_l(audio_l),
	.audio_r(audio_r),
	.out_l(audio_out_l),
	.out_r(audio_out_r)
);

// hdmi

wire [9:0] tmds_red, tmds_green, tmds_blue;
wire audio_sample; // audio sample locked strobe by hdmi module

hdmi #(.FS(SAMPLERATE), .N(6144)) hdmi(
	.I_CLK_PIXEL(p_clk_int),
	.I_RESET(pll_reset),
	.I_FREQ(hdmi_freq),
	.I_R(host_vga_r),
	.I_G(host_vga_g),
	.I_B(host_vga_b),
	.I_BLANK(host_vga_blank),
	.I_HSYNC(host_vga_hs),
	.I_VSYNC(host_vga_vs),
	.I_AUDIO_ENABLE(1'b1),
	.I_AUDIO_PCM_L(audio_out_l),
	.I_AUDIO_PCM_R(audio_out_r),
	.O_SAMPLE(audio_sample),
	.O_RED(tmds_red),
	.O_GREEN(tmds_green),
	.O_BLUE(tmds_blue)
);

hdmi_out_xilinx hdmiio(
	.clock_pixel_i(p_clk_int),
	.clock_tdms_i(clk_hdmi),
	.clock_tdms_n_i(clk_hdmi_n),
	.red_i(tmds_red),
	.green_i(tmds_green),
	.blue_i(tmds_blue),
	.tmds_out_p(tmds_p),
	.tmds_out_n(tmds_n)
);

endmodule
