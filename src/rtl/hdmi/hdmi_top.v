`timescale 1ns / 1ps
`default_nettype none

/*
 HDMI output of the Mini / Mini G: the video of the core (clk_ref, 28 MHz) or of the FT812
 (ft_sel, FT_CLK 24...80 MHz), with the audio of the core. The transmitter is zhdmi (hdmi_tx of
 karabas-go-modules, DVI when audio_en = 0); hdmi_pll makes the pixel and the 5x serial clocks
 for either source and tells the frequency.

 Audio: a sample is taken every CLKRATE / SAMPLERATE clocks of clk_ref and passed to the pixel
 clock with a toggle: the data stays the same for a whole sample period, far longer than the
 synchronizer takes, so it is stable when the pixel clock takes it. hdmi_tx measures the CTS of
 the audio clock regeneration from the pixel clock, so this works with any pixel clock.
*/

module hdmi_top #(
	parameter SAMPLERATE = 44100,
	parameter CLKRATE = 28000000 // clk_ref
) (
	input wire clk,       // 28 MHz of the core or FT_CLK (by ft_sel), measured by hdmi_pll
	input wire clk_ref,   // 28 MHz
	input wire clk_8,     // 8 MHz, the base of the FT pixel clock

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

	input wire audio_en,
	input wire [15:0] audio_l,
	input wire [15:0] audio_r,

	output wire [3:0] tmds_p,
	output wire [3:0] tmds_n,

	output wire [7:0] freq
);

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
assign host_vga_g = (ft_sel ? (~ft_data[26] ? 8'b0 : ft_data[15:8]) : (~vga_data[26] ? 8'b0 : vga_data[15:8]));
assign host_vga_b = (ft_sel ? (~ft_data[26] ? 8'b0 : ft_data[7:0]) : (~vga_data[26] ? 8'b0 : vga_data[7:0]));
assign host_vga_hs = (ft_sel ? ft_data[25] : vga_data[25]);
assign host_vga_vs = (ft_sel ? ft_data[24] : vga_data[24]);
assign host_vga_blank = (ft_sel ? ~ft_data[26] : ~vga_data[26]);

// audio samples in clk_ref, passed to the pixel clock
localparam integer SAMPLE_DIV = CLKRATE / SAMPLERATE;
reg [15:0] sample_cnt = 16'd0;
reg [31:0] sample_ref = 32'd0;
reg sample_tgl = 1'b0;
always @(posedge clk_ref) begin
	if (sample_cnt == SAMPLE_DIV - 1) begin
		sample_cnt <= 16'd0;
		sample_ref <= {audio_l, audio_r};
		sample_tgl <= ~sample_tgl;
	end
	else
		sample_cnt <= sample_cnt + 16'd1;
end

reg [2:0] sample_sync = 3'b000;
reg audio_clk = 1'b0;
reg signed [23:0] hdmi_audio_l = 24'd0, hdmi_audio_r = 24'd0;
always @(posedge p_clk_int) begin
	sample_sync <= {sample_sync[1:0], sample_tgl};
	audio_clk <= sample_sync[2] ^ sample_sync[1];
	if (sample_sync[2] ^ sample_sync[1]) begin
		hdmi_audio_l <= {sample_ref[31:16], 8'd0};
		hdmi_audio_r <= {sample_ref[15:0], 8'd0};
	end
end

// hdmi tx
hdmi_tx #(.SAMPLE_FREQ(SAMPLERATE)) hdmi_tx(
	.clk(p_clk_int),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(pll_reset || ~lockedx5),
	.rgb({host_vga_r, host_vga_g, host_vga_b}),
	.vsync(host_vga_vs),
	.hsync(host_vga_hs),
	.de(~host_vga_blank),

	.audio_en(audio_en),
	.audio_l(hdmi_audio_l),
	.audio_r(hdmi_audio_r),
	.audio_clk(audio_clk),

	.tx_clk_n(tmds_n[3]),
	.tx_clk_p(tmds_p[3]),
	.tx_d_n(tmds_n[2:0]),
	.tx_d_p(tmds_p[2:0]) // 0:blue, 1:green, 2:red
);

endmodule
