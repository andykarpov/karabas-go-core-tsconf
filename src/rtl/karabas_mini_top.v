`timescale 1ns / 1ps
`default_nettype none
`define HW_ID2

/*-------------------------------------------------------------------------------------------------------------------
-- 
-- 
-- #       #######                                                 #                                               
-- #                                                               #                                               
-- #                                                               #                                               
-- ############### ############### ############### ############### ############### ############### ############### 
-- #             #               # #                             # #             #               # #               
-- #             # ############### #               ############### #             # ############### ############### 
-- #             # #             # #               #             # #             # #             #               # 
-- #             # ############### #               ############### ############### ############### ############### 
--                                                                                                                 
--         ####### ####### ####### #######                                         ############### ############### 
--                                                                                 #               #             # 
--                                                                                 #   ########### #             # 
--                                                                                 #             # #             # 
-- https://github.com/andykarpov/karabas-go                                        ############### ############### 
--
-- FPGA TS-Conf core for Karabas-Go Mini
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- EU, 2024
------------------------------------------------------------------------------------------------------------------*/

module karabas_mini_top (
   //---------------------------
   input wire CLK_50MHZ,

	//---------------------------
	inout wire UART_RX,
	inout wire UART_TX,
	inout wire UART_CTS,
	inout wire ESP_RESET_N,
	inout wire ESP_BOOT_N,
	
   //---------------------------
   output wire [20:0] MA,
   inout wire [15:0] MD,
   output wire [1:0] MWR_N,
   output wire [1:0] MRD_N,

   //---------------------------
	output wire [1:0] SDR_BA,
	output wire [12:0] SDR_A,
	output wire SDR_CLK,
	output wire [1:0] SDR_DQM,
	output wire SDR_WE_N,
	output wire SDR_CAS_N,
	output wire SDR_RAS_N,
	inout wire [15:0] SDR_DQ,

   //---------------------------
   output wire SD_CS_N,
   output wire SD_CLK,
   inout wire SD_DI,
   inout wire SD_DO,
	input wire SD_DET_N,

   //---------------------------
   input wire [7:0] VGA_R,
   input wire [7:0] VGA_G,
   input wire [7:0] VGA_B,
   input wire VGA_HS,
   input wire VGA_VS,
	
   output wire [3:0] TMDS_P,
   output wire [3:0] TMDS_N,	
	
	//---------------------------
	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	input wire FT_AUDIO,
	input wire FT_DE,
	input wire FT_DISP,
	output wire FT_RESET,

	//---------------------------
	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,
	
   //---------------------------	
	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire AUDIO_L,
	output wire AUDIO_R,
	
	//---------------------------
	output wire ADC_CLK,
   inout wire ADC_BCK,
	inout wire ADC_LRCK,
   input wire ADC_DOUT,
	
	//---------------------------
	input wire MCU_CS_N,
	input wire MCU_SCK,
	input wire MCU_MOSI,
	output wire MCU_MISO,
	input wire [4:0] MCU_IO,
	
	//---------------------------
	output wire MIDI_TX,
	output wire MIDI_CLK,
	output wire MIDI_RESET_N,
	
	//---------------------------
	output wire FLASH_CS_N,
	input wire  FLASH_DO,
	output wire FLASH_DI,
	output wire FLASH_SCK,
	output wire FLASH_WP_N,
	output wire FLASH_HOLD_N	
   );

	assign ESP_RESET_N = 1'bZ;
	assign ESP_BOOT_N = 1'bZ;	
	assign FLASH_CS_N = 1'b1;
	assign FLASH_DI = 1'b1;
	assign FLASH_SCK = 1'b0;
	assign FLASH_WP_N = 1'b1;
	assign FLASH_HOLD_N = 1'b1;
	
	wire clk_sys;
	wire clk_8mhz;
	wire clk_bus;
	wire clk_16mhz;
	wire clk_12mhz;
	wire v_clk_int, v_clk_div2;
	wire p_clk_int;
	wire clk_hdmi, clk_hdmi_n;
   wire locked, lockedx5;
	wire areset;
	
	wire [7:0] hdmi_freq;
	reg [7:0] prev_hdmi_freq;
	reg hdmi_reset;

   pll pll (
	  .CLK_IN1(CLK_50MHZ),
	  .CLK_OUT1(clk_sys),
	  .CLK_OUT2(clk_8mhz),
	  .CLK_OUT3(clk_16mhz),
	  .CLK_OUT4(clk_12mhz),
	  .LOCKED(locked)
	);
	
	wire clk0, clkfx, clkfx180, clkdv;
	reg [7:0] pll_rst_cnt = 8'd0;
	wire pll_rst;
	reg prev_vdac2_sel;

/*	DCM_SP #(.CLKFX_DIVIDE(1), .CLKFX_MULTIPLY(5), .CLKDV_DIVIDE(2.0), .DESKEW_ADJUST("SOURCE_SYNCHRONOUS")) pllx5
   (
	 .CLKIN(v_clk_int),
	 .CLKFB(p_clk_int),
    .CLK0(clk0),
    .CLKFX(clkfx),
    .CLKFX180(clkfx180),
	 .CLKDV(clkdv),
    .LOCKED(lockedx5),
    .RST(pll_rst));
*/

wire clkfbout;
PLL_BASE #(
    .CLKIN_PERIOD(13.0),
	 .CLKFBOUT_MULT(10),
	 .CLKOUT0_DIVIDE(2),
	 .CLKOUT1_DIVIDE(2),
	 .CLKOUT1_PHASE(180.0),
	 .CLKOUT2_DIVIDE(10),
	 .CLKOUT3_DIVIDE(20),
	 .COMPENSATION("INTERNAL")
  ) pllx5 
  (
	.CLKIN(v_clk_int),
	.CLKFBIN(clkfbout),
	.CLKFBOUT(clkfbout),
	.RST(pll_rst),
	.LOCKED(lockedx5),
	.CLKOUT0(clkfx), // 5x
	.CLKOUT1(clkfx180), // 5x 180deg
	.CLKOUT2(clk0), // 1x
	.CLKOUT3(clkdv) // div2
  );
	 
  BUFG clkout1_buf (.O(clk_hdmi), .I(clkfx));
  BUFG clkout2_buf (.O(clk_hdmi_n), .I(clkfx180));
  BUFG clkout3_buf (.O(p_clk_int), .I(clk0));
  BUFG clkout4_buf (.O(v_clk_div2), .I(clkdv));

  always @(posedge v_clk_int)
  begin
	if ((prev_vdac2_sel != vdac2_sel) || kb_reset || areset || hdmi_reset) begin
		pll_rst_cnt <= 8'b10000000;
	end
	prev_vdac2_sel <= vdac2_sel;
	if (pll_rst_cnt > 0) pll_rst_cnt <= pll_rst_cnt+1;
  end
  assign pll_rst = pll_rst_cnt[7];

	// midi clk
	ODDR2 u_midi_clk (
		.Q(MIDI_CLK),
		.C0(clk_12mhz),
		.C1(~clk_12mhz),
		.CE(1'b1),
		.D0(1'b1),
		.D1(1'b0),
		.R(1'b0),
		.S(1'b0)
	);
	
	assign areset = ~locked;
	
	reg ce_28m;
	reg [1:0] div = 2'd0;
	always @(negedge clk_sys) 
	begin
		div <= div + 1'd1;
		if(div == 2) div <= 0;
		ce_28m <= !div;
	end

	reg ce_14m;
	always @(posedge clk_bus)
	begin
		ce_14m <= ~ce_14m;
	end 
	
	reg tape_in_r;
	always @(posedge clk_bus)
	begin
		tape_in_r <= TAPE_IN;
	end 
	
	wire [7:0] video_r;
	wire [7:0] video_g;
	wire [7:0] video_b;
	wire [7:0] osd_r;
	wire [7:0] osd_g;
	wire [7:0] osd_b;
	wire video_hsync;
	wire video_vsync;
	wire video_blank;
	wire btn_reset_n, btn_reset_gs_n;
	wire audio_beeper;
	wire [15:0] audio_out_l;
	wire [15:0] audio_out_r;
	wire [31:0] audio_mix_l;
	wire [31:0] audio_mix_r;
	wire [12:0] joy_l;
	wire [12:0] joy_r;
	wire [2:0] mouse_addr;
	reg [7:0] mouse_data;
	wire [15:8] keyboard_addr;
	wire [4:0] keyboard_data;
	wire [7:0] keyboard_scancode;
	wire [7:0] rtc_addr;
	wire [7:0] rtc_di;
	wire [7:0] rtc_do;
	wire rtc_wr, rtc_rd;
	wire [7:0] uart_rx_data;
	wire [7:0] uart_rx_idx;
	wire [7:0] uart_tx_data;
	wire uart_tx_wr;
	wire [7:0] uart_dlm;
	wire [7:0] uart_dll;
	wire uart_dll_wr, uart_dlm_wr, uart_tx_mode;
	wire [7:0] hid_kb_status;
	wire [7:0] hid_kb_dat0;
	wire [7:0] hid_kb_dat1;
	wire [7:0] hid_kb_dat2;
	wire [7:0] hid_kb_dat3;
	wire [7:0] hid_kb_dat4;
	wire [7:0] hid_kb_dat5;
	wire [7:0] ps2_scancode;
	wire ps2_scancode_upd;
	wire loader_act;
	wire [31:0] loader_addr;
	wire [7:0] loader_data;
	wire loader_wr;
	wire [15:0] softsw_command;
	wire [15:0] osd_command;
	wire [2:0] kb_joy_type_l;
	wire [2:0] kb_joy_type_r;
	wire kb_vga_60hz;
	wire [7:0] joy_bus;
	wire kb_pause;
	wire kb_reset;
	wire kb_reset_gs;
	wire kb_nmi;
	wire mcu_busy;
	wire f1;

	tsconf tsconf (
     .clk(clk_sys),
	  .clk8(clk_8mhz),
	  .ce(ce_28m),
	  .resetbtn_n(btn_reset_n),	
		.resetgsbtn_n(btn_reset_gs_n),
	  .locked(locked),
	  .clk_bus(clk_bus),
	  .f1_out(f1),
	  
	  .sram_addr(MA),
	  .sram_data(MD),
     .sram_we_n(MWR_N),
     .sram_rd_n(MRD_N),
	  
     .VGA_R(video_r),
     .VGA_G(video_g),
     .VGA_B(video_b),
     .VGA_HS(video_hsync),
     .VGA_VS(video_vsync),	
	  .VGA_BLANK(video_blank),
     
	  .beep(audio_beeper),
	  .audio_out_l(audio_out_l),
	  .audio_out_r(audio_out_r),

	  .sdcs_n(SD_CS_N),
     .sdclk(SD_CLK),
     .sddo(SD_DI),
     .sddi(SD_DO),
	  
	  .ftcs_n(ftcs_n),
	  .ftclk(ftclk),
	  .ftdo(ftdo),
	  .ftdi(ftdi),
	  .ftint(ftint),
	  .vdac2_sel(vdac2_sel),
	  
	  .joy_data (joy_bus),

	  .mouse_addr(mouse_addr),
	  .mouse_data(mouse_data),
		
	  .keyboard_addr(keyboard_addr),
	  .keyboard_data(keyboard_data),
	  .keyboard_scancode(keyboard_scancode),
		
	  .rtc_addr(rtc_addr),
	  .rtc_di(rtc_di),
	  .rtc_do(rtc_do_mapped),
	  .rtc_wr(rtc_wr),
	  .rtc_rd(rtc_rd),
	  
	  .uart_rx(UART_RX),
	  .uart_tx(UART_TX),
	  .uart_cts(UART_CTS),
	  
	  .ide_d(WD),
	  .ide_rs_n(WRESET_N),
	  .ide_a(WA),
	  .ide_dir(),
	  .ide_cs0_n(WCS_N[0]),
	  .ide_cs1_n(WCS_N[1]),
	  .ide_rd_n(WRD_N),
	  .ide_wr_n(WWR_N),
	  .ide_rdy(),
	  
	  .tape_in(tape_in_r),
	  .tape_out(TAPE_OUT),
	  
	  .covox_en(covox_en),
	  .psg_mix(psg_mix),
	  .psg_type(psg_type),
	  .vga_60hz(kb_vga_60hz),
	  
	  .loader_act(loader_act),
	  .loader_a(loader_addr),
	  .loader_d(loader_data),
	  .loader_wr(loader_wr),
	  
	  .usb_uart_rx_data(uart_rx_data),
	  .usb_uart_rx_idx(uart_rx_idx),	 
	  .usb_uart_tx_data(uart_tx_data),
	  .usb_uart_tx_wr(uart_tx_wr),
	  .usb_uart_tx_mode(uart_tx_mode),
	  .usb_uart_dll(uart_dll),
	  .usb_uart_dlm(uart_dlm),
	  .usb_uart_dll_wr(uart_dll_wr),
	  .usb_uart_dlm_wr(uart_dlm_wr),

		.sdram_clk(SDR_CLK),
      .sdram_ba(SDR_BA),
      .sdram_a(SDR_A),
      .sdram_dqm(SDR_DQM),
      .sdram_we_n(SDR_WE_N),
      .sdram_cas_n(SDR_CAS_N),
      .sdram_ras_n(SDR_RAS_N),
      .sdram_dq(SDR_DQ),
		
		.midi_reset_n(MIDI_RESET_N),
		.midi_tx(MIDI_TX)
	  
	 );
	 
wire [7:0] rtc_do_mapped;
	 
wire ftcs_n, ftclk, ftdo, ftdi, ftint, vdac2_sel;
wire mcu_ft_spi_on, mcu_ft_vga_on, mcu_ft_sck, mcu_ft_mosi, mcu_ft_cs_n, mcu_ft_reset;

wire [7:0] host_vga_r, host_vga_g, host_vga_b;
wire host_vga_hs, host_vga_vs, host_vga_blank;

reg host_vga_hs_r, host_vga_vs_r, host_vga_blank_r, host_vga_hs_r2, host_vga_vs_r2, host_vga_blank_r2;
reg [7:0] host_vga_r_r, host_vga_g_r, host_vga_b_r, host_vga_r_r2, host_vga_g_r2, host_vga_b_r2;
reg [15:0] audio_mix_l_r, audio_mix_r_r, audio_mix_l_r2, audio_mix_r_r2;
wire vga_hs_ibuf, vga_vs_ibuf, ft_de_ibuf;
wire vga_hs_buf, vga_vs_buf, ft_de_buf;

IBUF vga_hs_buf0 (.I(VGA_HS), .O(vga_hs_buf));
IBUF vga_vs_buf0 (.I(VGA_VS), .O(vga_vs_buf));
IBUF ft_de_buf0 (.I(FT_DE), .O(ft_de_buf));

always @(posedge v_clk_int)
begin
	host_vga_hs_r <= (vdac2_sel ? vga_hs_buf : video_hsync); host_vga_hs_r2 <= host_vga_hs_r;
	host_vga_vs_r <= (vdac2_sel ? vga_vs_buf : video_vsync); host_vga_vs_r2 <= host_vga_vs_r;
	host_vga_blank_r <= (vdac2_sel ? ~ft_de_buf : video_blank);   host_vga_blank_r2  <= host_vga_blank_r;
	host_vga_r_r <= (vdac2_sel ? VGA_R : osd_r);    host_vga_r_r2 <= host_vga_r_r;
	host_vga_g_r <= (vdac2_sel ? VGA_G : osd_g);    host_vga_g_r2 <= host_vga_g_r;
	host_vga_b_r <= (vdac2_sel ? VGA_B : osd_b);    host_vga_b_r2 <= host_vga_b_r;
	audio_mix_l_r <= audio_mix_l; audio_mix_l_r2 <= audio_mix_l_r;
	audio_mix_r_r <= audio_mix_r; audio_mix_r_r2 <= audio_mix_r_r;
end

assign host_vga_r = host_vga_blank_r2 ? 8'b0 : host_vga_r_r2;
assign host_vga_g = host_vga_blank_r2 ? 8'b0 : host_vga_g_r2;
assign host_vga_b = host_vga_blank_r2 ? 8'b0 : host_vga_b_r2;
assign host_vga_hs = host_vga_hs_r2;
assign host_vga_vs = host_vga_vs_r2;
assign host_vga_blank = host_vga_blank_r2;

/*assign host_vga_r = (vdac2_sel ? VGA_R[7:0] : osd_r[7:0]);
assign host_vga_g = (vdac2_sel ? VGA_G[7:0] : osd_g[7:0]);
assign host_vga_b = (vdac2_sel ? VGA_B[7:0] : osd_b[7:0]);
assign host_vga_hs = (vdac2_sel ? VGA_HS : video_hsync);
assign host_vga_vs = (vdac2_sel ? VGA_VS : video_vsync);
assign host_vga_blank = (vdac2_sel ? ~FT_DE : video_blank);
*/

assign FT_SPI_CS_N = mcu_ft_spi_on ? mcu_ft_cs_n : ftcs_n;
assign FT_SPI_SCK = mcu_ft_spi_on ? mcu_ft_sck : ftclk;
assign ftdi = FT_SPI_MISO;
assign FT_SPI_MOSI = mcu_ft_spi_on ? mcu_ft_mosi : ftdo;
assign ftint = FT_INT_N;
assign FT_RESET = ~mcu_ft_reset; // 1'b1

wire ft_clk_ibuf;
IBUF ft_clk_buf0 (.I(FT_CLK), .O(ft_clk_ibuf));

BUFGMUX v_clk_mux(
 .I0(ce_28m),
 .I1(ft_clk_ibuf),
 .O(v_clk_int),
 .S(vdac2_sel)
);

wire [9:0] tmds_red, tmds_green, tmds_blue;

always @(posedge v_clk_int)
begin
	hdmi_reset <= 1'b0;
	if (prev_hdmi_freq != hdmi_freq) hdmi_reset <= 1'b1;
	prev_hdmi_freq <= hdmi_freq;
end

freq_counter freq_counter_inst(
	.i_clk_ref(clk_bus),
	.i_clk_test(v_clk_int),
	.i_reset(areset),
	.o_freq(hdmi_freq)
);

hdmi hdmi(
	.I_CLK_PIXEL(v_clk_int),
	//.I_RESET(pll_rst || hdmi_reset),
	.I_RESET(hdmi_reset || ~lockedx5),
	.I_FREQ(hdmi_freq),
	.I_R(host_vga_r),
	.I_G(host_vga_g),
	.I_B(host_vga_b),
	.I_BLANK(host_vga_blank),
	.I_HSYNC(host_vga_hs),
	.I_VSYNC(host_vga_vs),
	.I_AUDIO_ENABLE(1'b1),
	.I_AUDIO_PCM_L(audio_mix_l_r2[15:0]),
	.I_AUDIO_PCM_R(audio_mix_r_r2[15:0]),
	.O_RED(tmds_red),
	.O_GREEN(tmds_green),
	.O_BLUE(tmds_blue)
);

hdmi_out_xilinx hdmiio(
	.clock_pixel_i(v_clk_int),
	.clock_tdms_i(clk_hdmi),
	.clock_tdms_n_i(clk_hdmi_n),
	.red_i(tmds_red),
	.green_i(tmds_green),
	.blue_i(tmds_blue),
	.tmds_out_p(TMDS_P),
	.tmds_out_n(TMDS_N)
);

//------- Sigma-Delta DAC ---------
dac dac_l(
	.I_CLK(clk_sys),
	.I_RESET(areset),
	.I_DATA({2'b00, !audio_mix_l[15], audio_mix_l[14:4], 2'b00}),
	.O_DAC(AUDIO_L)
);

dac dac_r(
	.I_CLK(clk_sys),
	.I_RESET(areset),
	.I_DATA({2'b00, !audio_mix_r[15], audio_mix_r[14:4], 2'b00}),
	.O_DAC(AUDIO_R)
);

wire adc_clk_int;
BUFGMUX ADC_CLK_MUX(
 .I0(v_clk_int),
 .I1(v_clk_div2),
 .O(adc_clk_int),
 .S(adc_div2)
);

wire adc_div2 = (hdmi_freq > 32) ? 1'b1 : 1'b0;

// ------- PCM1808 ADC ---------
wire signed [23:0] adc_l, adc_r;

i2s_transceiver adc(
	.reset_n(~areset),
	.mclk(adc_clk_int),
	.sclk(ADC_BCK),
	.ws(ADC_LRCK),
	.sd_tx(),
	.sd_rx(ADC_DOUT),
	.l_data_tx(24'b0),
	.r_data_tx(24'b0),
	.l_data_rx(adc_l),
	.r_data_rx(adc_r)
);

// ------- ADC_CLK output buf
ODDR2 oddr_adc2(
	.Q(ADC_CLK),
	.C0(adc_clk_int),
	.C1(~adc_clk_int),
	.CE(1'b1),
	.D0(1'b1),
	.D1(1'b0),
	.R(1'b0),
	.S(1'b0)
);

// ------- audio mix host + adc
assign audio_mix_l = audio_out_l[15:0] + adc_l[23:8];
assign audio_mix_r = audio_out_r[15:0] + adc_r[23:8];

//---------- MCU ------------

mcu mcu(
	.CLK(clk_bus),
	.N_RESET(~areset),
	
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(MCU_SCK),
	.MCU_SS(MCU_CS_N),
	
	.MCU_SPI_FT_SS(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),	
	
	.MS_X(ms_x),
	.MS_Y(ms_y),
	.MS_Z(ms_z),
	.MS_B(ms_b),
	.MS_UPD(ms_upd),
	
	.KB_STATUS(hid_kb_status),
	.KB_DAT0(hid_kb_dat0),
	.KB_DAT1(hid_kb_dat1),
	.KB_DAT2(hid_kb_dat2),
	.KB_DAT3(hid_kb_dat3),
	.KB_DAT4(hid_kb_dat4),
	.KB_DAT5(hid_kb_dat5),
	
	.KB_SCANCODE(ps2_scancode),
	.KB_SCANCODE_UPD(ps2_scancode_upd),
	
	.XT_SCANCODE(),
	.XT_SCANCODE_UPD(),	
	
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	
	.RTC_A(rtc_addr),
	.RTC_DI(rtc_di),
	.RTC_DO(rtc_do),
	.RTC_CS(1'b1),
	.RTC_WR_N(~rtc_wr),
	
	.UART_RX_DATA(uart_rx_data),
	.UART_RX_IDX(uart_rx_idx),	 
	.UART_TX_DATA(uart_tx_data),
	.UART_TX_WR(uart_tx_wr),
	
	.UART_TX_MODE(uart_tx_mode),
	.UART_DLL(uart_dll),
	.UART_DLM(uart_dlm),
	.UART_DLL_WR(uart_dll_wr),
	.UART_DLM_WR(uart_dlm_wr),
	
	.ROMLOADER_ACTIVE(loader_act),
	.ROMLOAD_ADDR(loader_addr),
	.ROMLOAD_DATA(loader_data),
	.ROMLOAD_WR(loader_wr),
	
	.SOFTSW_COMMAND(softsw_command),	
	.OSD_COMMAND(osd_command),
	
	.FT_SPI_ON(mcu_ft_spi_on),
	.FT_VGA_ON(mcu_ft_vga_on),
	.FT_SCK(mcu_ft_sck),
	.FT_MISO(FT_SPI_MISO),
	.FT_MOSI(mcu_ft_mosi),
	.FT_CS_N(mcu_ft_cs_n),
	.FT_RESET(mcu_ft_reset),
	
	.DEBUG_ADDR(16'd0),
	.DEBUG_DATA({8'd0, hdmi_freq}),
	
	.BUSY(mcu_busy)
);

//---------- Keyboard parser ------------

hid_parser hid_parser(
	.CLK(clk_bus),
	.RESET(areset),

	.KB_STATUS(hid_kb_status),
	.KB_DAT0(hid_kb_dat0),
	.KB_DAT1(hid_kb_dat1),
	.KB_DAT2(hid_kb_dat2),
	.KB_DAT3(hid_kb_dat3),
	.KB_DAT4(hid_kb_dat4),
	.KB_DAT5(hid_kb_dat5),
	
	.KB_SCANCODE(ps2_scancode),
	.KB_SCANCODE_UPD(ps2_scancode_upd),
	
	.JOY_TYPE_L(kb_joy_type_l),
	.JOY_TYPE_R(kb_joy_type_r),
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	
	.KB_TYPE(1'b1),
	.A (keyboard_addr),	
	
	.JOY_DO(joy_bus),
	.KB_DO(keyboard_data),
	
	.RTC_A(rtc_addr),
	.RTC_WR(rtc_wr),
	.RTC_RD(rtc_rd),
	.RTC_DI(rtc_di),
	.RTC_DO_IN(rtc_do),
	.RTC_DO_OUT(rtc_do_mapped)
);

//---------- Soft switches ------------

wire covox_en;
wire [1:0] psg_mix;
wire psg_type;

soft_switches soft_switches(
	.CLK(clk_bus),
	
	.SOFTSW_COMMAND(softsw_command),
	
	.COVOX_EN(covox_en),
	.PSG_MIX(psg_mix),
	.PSG_TYPE(psg_type),
	.JOY_TYPE_L(kb_joy_type_l),
	.JOY_TYPE_R(kb_joy_type_r),
	.VGA_60HZ(kb_vga_60hz),
	.PAUSE(kb_pause),
	.RESET_GS(kb_reset_gs),
	.NMI(kb_nmi),
	.RESET(kb_reset)
);

assign btn_reset_n = ~kb_reset & ~mcu_busy;
assign btn_reset_gs_n = ~kb_reset_gs & ~mcu_busy;

//---------- Mouse / cursor ------------

wire [7:0] ms_x, ms_y, cursor_x, cursor_y;
wire [3:0] ms_z, cursor_z;
wire [2:0] ms_b, cursor_b;
wire ms_upd;

cursor cursor(
	.CLK(clk_bus),
	.RESET(areset),
	
	.MS_X(ms_x),
	.MS_Y(ms_y),
	.MS_Z(ms_z),
	.MS_B(ms_b),
	.MS_UPD(ms_upd),
	
	.OUT_X(cursor_x),
	.OUT_Y(cursor_y),
	.OUT_Z(),
	.OUT_B(cursor_b)
);

always @* begin
	case (mouse_addr)
		3'b010: mouse_data <= {5'b11111, ~cursor_b[2:0]};
		3'b011: mouse_data <= cursor_x;
		3'b110: mouse_data <= {5'b11111, ~cursor_b[2:0]};
		3'b111: mouse_data <= cursor_y;
		default: mouse_data <= 8'hFF;
	endcase
end

//--------- OSD --------------

overlay overlay(
	.CLK(clk_bus),
	.RGB_I({video_r[7:0], video_g[7:0], video_b[7:0]}),
	.RGB_O({osd_r[7:0], osd_g[7:0], osd_b[7:0]}),
	.HSYNC_I(video_hsync),
	.VSYNC_I(video_vsync),
	.OSD_COMMAND(osd_command)
);

endmodule
