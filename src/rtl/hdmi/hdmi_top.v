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
	input wire clk,       // FT_CLK: the FT812 video is taken on its falling edge, hdmi_pll measures it
	input wire clk_ref,   // 28 MHz
	input wire clk_ref_pll, // clk_ref before its BUFG (the PLL output): the BUFGMUXes of hdmi_pll
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
	.clk_ref_pll(clk_ref_pll),
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

// What goes from clk_ref into the pixel clock leaves registers on the falling clk_ref (the video, ft_sel, audio_en,
// the reset of hdmi_tx, the audio sample): in the mode of the core the pixel clock is clk_ref through the BUFGMUX of
// hdmi_pll, about 4 ns later than the BUFG of clk_ref by trce, so half a period on each side instead of a hold of
// some 1 ns. In the FT mode the pixel clock is not related to clk_ref: ft_sel, audio_en and the reset go through
// two flip-flops (the reset is set at once and released two pixel clocks later).
reg [26:0] vga_data_n = 27'd0;
reg ft_sel_n = 1'b0, audio_en_n = 1'b0, pll_reset_n = 1'b1;
always @(negedge clk_ref) begin
	vga_data_n <= {vga_de, vga_hs, vga_vs, vga_rgb[23:0]};
	ft_sel_n <= ft_sel;
	audio_en_n <= audio_en;
	pll_reset_n <= pll_reset;
end
reg [1:0] ft_sel_s = 2'b00, audio_en_s = 2'b00;
reg [1:0] tx_reset_s = 2'b11;
wire tx_reset_a = pll_reset_n || ~lockedx5;
always @(posedge p_clk_int) begin
	ft_sel_s <= {ft_sel_s[0], ft_sel_n};
	audio_en_s <= {audio_en_s[0], audio_en_n};
end
always @(posedge p_clk_int or posedge tx_reset_a)
	if (tx_reset_a)
		tx_reset_s <= 2'b11;
	else
		tx_reset_s <= {tx_reset_s[0], 1'b0};
wire ft_sel_p = ft_sel_s[1];

// mux signals
wire [7:0] host_vga_r, host_vga_g, host_vga_b;
wire host_vga_hs, host_vga_vs, host_vga_blank;

// The video of the core: in its mode the pixel clock is clk_ref, the clock of the video (vga_data_n above, then
// one register).
reg [26:0] vga_data = 27'd0;
always @(posedge p_clk_int)
	vga_data <= vga_data_n;

// The video of the FT812: taken at the falling FT_CLK (the FT812 changes it with the rising one), then through an
// asynchronous fifo into the pixel clock, which has the frequency of FT_CLK (both from clk_8) and an unknown phase:
// two registers in a row took bits of two pixels into one when the edges came together. Reading starts when the
// fifo is half full and starts again (from half full) if it ever ran empty. The write side of the fifo runs on the
// falling FT_CLK as well: ft_in sits in the input flip-flops of the pads, far from the fifo, and half a period of
// 80 MHz is shorter than that route.
reg [26:0] ft_in = 27'd0;
always @(negedge clk)
	ft_in <= {ft_de, ft_hs, ft_vs, ft_rgb[23:0]};

reg [1:0] ft_reset_s = 2'b11; // tx_reset_a released on the falling FT_CLK
always @(negedge clk or posedge tx_reset_a)
	if (tx_reset_a)
		ft_reset_s <= 2'b11;
	else
		ft_reset_s <= {ft_reset_s[0], 1'b0};

wire [26:0] ft_data;
wire ft_empty;
wire [3:0] ft_count;
reg ft_rd = 1'b0;
kg_async_fifo #(.DW(27), .AW(3)) ft_fifo(
	.wclk(~clk), .wreset(ft_reset_s[1]), .wr(1'b1), .din(ft_in), .full(),
	.rclk(p_clk_int), .rreset(tx_reset_s[1]), .rd(ft_rd), .dout(ft_data), .empty(ft_empty), .rcount(ft_count)
);
always @(posedge p_clk_int)
	if (tx_reset_s[1] || ft_empty)
		ft_rd <= 1'b0;
	else if (ft_count >= 4'd4)
		ft_rd <= 1'b1;

assign host_vga_r = (ft_sel_p ? (~ft_data[26] ? 8'b0 : ft_data[23:16]) : (~vga_data[26] ? 8'b0 : vga_data[23:16]));
assign host_vga_g = (ft_sel_p ? (~ft_data[26] ? 8'b0 : ft_data[15:8]) : (~vga_data[26] ? 8'b0 : vga_data[15:8]));
assign host_vga_b = (ft_sel_p ? (~ft_data[26] ? 8'b0 : ft_data[7:0]) : (~vga_data[26] ? 8'b0 : vga_data[7:0]));
assign host_vga_hs = (ft_sel_p ? ft_data[25] : vga_data[25]);
assign host_vga_vs = (ft_sel_p ? ft_data[24] : vga_data[24]);
assign host_vga_blank = (ft_sel_p ? ~ft_data[26] : ~vga_data[26]);

// audio samples in clk_ref (on its falling edge, see above), passed to the pixel clock
localparam integer SAMPLE_DIV = CLKRATE / SAMPLERATE;
reg [15:0] sample_cnt = 16'd0;
reg [31:0] sample_ref = 32'd0;
reg sample_tgl = 1'b0;
always @(negedge clk_ref) begin
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
	.reset(tx_reset_s[1]),
	.rgb({host_vga_r, host_vga_g, host_vga_b}),
	.vsync(host_vga_vs),
	.hsync(host_vga_hs),
	.de(~host_vga_blank),

	.audio_en(audio_en_s[1]),
	.audio_l(hdmi_audio_l),
	.audio_r(hdmi_audio_r),
	.audio_clk(audio_clk),

	.tx_clk_n(tmds_n[3]),
	.tx_clk_p(tmds_p[3]),
	.tx_d_n(tmds_n[2:0]),
	.tx_d_p(tmds_p[2:0]) // 0:blue, 1:green, 2:red
);

endmodule
