`timescale 1ns / 1ps
`default_nettype none

module zhdmi_top(

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
	
	output wire [7:0] freq,
	output wire samplerate_stb
);

parameter SAMPLERATE = 192000;
parameter CLKRATE = 28000000;

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
always @(posedge p_clk_int) begin
	ft_data_r2[26:0] <= ft_data_r[53:27];
	ft_data_r2[53:27] <= ft_data_r2[26:0];
end
assign ft_data = ft_data_r2[53:27];
assign vga_data = {vga_de, vga_hs, vga_vs, vga_rgb[23:0]};

assign host_vga_r = (ft_sel ? (~ft_data[26] ? 8'b0 : ft_data[23:16]) : (~vga_data[26] ? 8'b0 : vga_data[23:16]));
assign host_vga_g = (ft_sel ? (~ft_data[26] ? 8'b0 : ft_data[16:8]) : (~vga_data[26] ? 8'b0 : vga_data[15:8]));
assign host_vga_b = (ft_sel ? (~ft_data[26] ? 8'b0 : ft_data[7:0]) : (~vga_data[26] ? 8'b0 : vga_data[7:0]));
assign host_vga_hs = (ft_sel ? ft_data[25] : vga_data[25]);
assign host_vga_vs = (ft_sel ? ft_data[24] : vga_data[24]);
assign host_vga_blank = (ft_sel ? ~ft_data[26] : ~vga_data[26]);

wire [15:0] audio_out_l, audio_out_r;
wire audio_clk;
audio_restrober #(.SAMPLERATE(SAMPLERATE), .CLKRATE(CLKRATE)) audio_restrober(
	.clk(p_clk_int),
	.clk_ref(clk_ref),
	.reset(reset || ~lockedx5),
	.freq(hdmi_freq),
	.audio_l(audio_l),
	.audio_r(audio_r),
	.out_l(audio_out_l),
	.out_r(audio_out_r),
	.out_clk(audio_clk)
);
assign samplerate_stb = audio_clk;

reg signed [23:0] hdmi_audio_l, hdmi_audio_r;
always @(posedge p_clk_int) begin
	if (audio_clk) begin
		hdmi_audio_l <= $signed(audio_out_l) * 256;
		hdmi_audio_r <= $signed(audio_out_r) * 256;
	end
end

// hdmi tx
hdmi_tx #(.SAMPLE_FREQ(SAMPLERATE)) hdmi_tx(
	.clk(p_clk_int),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(reset || ~lockedx5),
	.rgb({host_vga_r, host_vga_g, host_vga_b}),
	.vsync(host_vga_vs),
	.hsync(host_vga_hs),
	.de(~host_vga_blank),
	
	.audio_en(1'b1),
	.audio_l(hdmi_audio_l),
	.audio_r(hdmi_audio_r),
	.audio_clk(audio_clk),
	
	.tx_clk_n(tmds_n[3]),
	.tx_clk_p(tmds_p[3]),
	.tx_d_n(tmds_n[2:0]),
	.tx_d_p(tmds_p[2:0]) // 0:blue, 1:green, 2:red
);


endmodule
