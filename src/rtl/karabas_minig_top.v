`timescale 1ns / 1ps
`default_nettype none
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
-- EU, 2024-2025
------------------------------------------------------------------------------------------------------------------*/

// Warning! HW_ID2 and HW_ID3 macroses are defined in the Synthesize - XST process properties!

module karabas_minig_top (
	//------------------ global clock --------
	input wire 				CLK_50MHZ,

	//------------------ esp8266 uart --------
	inout wire 				UART_RX,
	inout wire 				UART_TX,
	inout wire 				UART_CTS,

	//------------------ sram ----------------
	output wire [20:0] 	MA,
	inout wire [15:0] 	MD,
	output wire [1:0] 	MWR_N,
	output wire [1:0] 	MRD_N,

	//------------------ sdram ---------------
	output wire [1:0] 	SDR_BA,
	output wire [12:0] 	SDR_A,
	output wire 			SDR_CLK,
	output wire [1:0] 	SDR_DQM,
	output wire 			SDR_WE_N,
	output wire 			SDR_CAS_N,
	output wire 			SDR_RAS_N,
	inout wire [15:0] 	SDR_DQ,

	//------------------ sd2 -----------------
	output wire 			SD_CS_N,
	output wire 			SD_CLK,
	inout wire 				SD_DI,
	inout wire 				SD_DO,
	input wire 				SD_DET_N,

	//------------------ ft812 rgb + sync ----
	input wire [7:0] 		VGA_R,
	input wire [7:0] 		VGA_G,
	input wire [7:0] 		VGA_B,
	input wire 				VGA_HS,
	input wire 				VGA_VS,

	//------------------ dvi / hdmi ----------
	output wire [3:0] 	TMDS_P,
	output wire [3:0] 	TMDS_N,

	//------------------ ft812 spi and ctl ---
	output wire 			FT_SPI_CS_N,
	output wire 			FT_SPI_SCK,
	input wire 				FT_SPI_MISO,
	output wire 			FT_SPI_MOSI,
	input wire 				FT_INT_N,
	input wire 				FT_CLK,
	input wire 				FT_DE,
	output wire 			FT_CLK_OUT,

	//------------------ cf card -------------
	output wire [2:0] 	WA,
	output wire [1:0] 	WCS_N,
	output wire 			WRD_N,
	output wire 			WWR_N,
	output wire 			WRESET_N,
	inout wire [15:0] 	WD,

	//------------------ analog in/out -------	
	output wire 			TAPE_OUT,
	input wire 				TAPE_IN,

   //------------------ i2s dac -------------
	output wire          DAC_BCK,
	output wire          DAC_WS,
	output wire          DAC_DAT,

	//------------------ adc -----------------
	output wire 			ADC_CLK,
	inout wire 				ADC_BCK,
	inout wire 				ADC_LRCK,
	input wire 				ADC_DOUT,
	
	//------------------ esp32 i2s and cs ----
	output wire          ESP32_SPI_CS_N,
	input wire           ESP32_PCM_BCK,
	input wire           ESP32_PCM_RLCK,
	input wire           ESP32_PCM_DAT,	

	//------------------ mcu spi -------------
	input wire 				MCU_CS_N,
	input wire 				MCU_SCK,
	input wire 				MCU_MOSI,
	output wire 			MCU_MISO,
	input wire [5:0] 		MCU_IO,

	//------------------ midi ----------------
	output wire 			MIDI_TX,

	//------------------ optional flash ------
	output wire 			FLASH_CS_N,
	input wire  			FLASH_DO,
	output wire 			FLASH_DI,
	output wire 			FLASH_SCK,
	output wire 			FLASH_WP_N,
	output wire 			FLASH_HOLD_N
);

// unused signals yet
assign FLASH_CS_N 	= 1'b1;
assign FLASH_DI 		= 1'b1;
assign FLASH_SCK 		= 1'b0;
assign FLASH_WP_N 	= 1'b1;
assign FLASH_HOLD_N 	= 1'b1;

// system clocks
wire clk_sys, clk_8mhz, clk_bus, clk_16mhz, clk_12mhz, v_clk_int;
wire locked, areset;

pll pll (
	.CLK_IN1				(CLK_50MHZ),
	.CLK_OUT1			(clk_sys),
	.CLK_OUT2			(clk_8mhz),
	.CLK_OUT3			(clk_16mhz),
	.CLK_OUT4			(clk_12mhz),
	.LOCKED				(locked)
);

// ft clk 8mhz out
ODDR2 u_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8mhz), .C1(~clk_8mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

assign areset = ~locked;

// 28 MHz CE
reg ce_28m;
reg [1:0] div = 2'd0;
always @(negedge clk_sys) 
begin
	div <= div + 1'd1;
	if(div == 2) div <= 0;
	ce_28m <= !div;
end

// 14 MHz CE
reg ce_14m;
always @(posedge clk_bus)
begin
	ce_14m <= ~ce_14m;
end

// tape in reg
reg tape_in_r;
always @(posedge clk_bus)
begin
	tape_in_r <= TAPE_IN;
end

// tsconf core
wire [7:0] video_r, video_g, video_b, osd_r, osd_g, osd_b;
wire video_hsync, video_vsync, video_blank;
wire btn_reset_n, btn_reset_gs_n;
wire audio_beeper;
wire [15:0] audio_out_l, audio_out_r;
wire [15:0] audio_mix_l, audio_mix_r;
wire [12:0] joy_l, joy_r;
wire [2:0] mouse_addr;
reg [7:0] mouse_data;
wire [15:8] keyboard_addr;
wire [4:0] keyboard_data;
wire [7:0] keyboard_scancode;
wire [7:0] rtc_addr;
wire [7:0] rtc_di, rtc_do;
wire rtc_wr, rtc_rd;
wire [7:0] uart_rx_data, uart_rx_idx, uart_tx_data;
wire uart_tx_wr;
wire [7:0] uart_dlm, uart_dll;
wire uart_dll_wr, uart_dlm_wr, uart_tx_mode;
wire [7:0] hid_kb_status, hid_kb_dat0, hid_kb_dat1, hid_kb_dat2, hid_kb_dat3, hid_kb_dat4, hid_kb_dat5;
wire [7:0] ps2_scancode;
wire ps2_scancode_upd;
wire loader_act;
wire [31:0] loader_addr;
wire [7:0] loader_data;
wire loader_wr;
wire [15:0] softsw_command;
wire [15:0] osd_command;
wire [2:0] kb_joy_type_l, kb_joy_type_r;
wire kb_vga_60hz;
wire [7:0] joy_bus;
wire kb_pause, kb_reset, kb_reset_gs, kb_nmi, mcu_busy;
wire f1;

tsconf tsconf (
	.clk					(clk_sys),
	.clk8					(clk_8mhz),
	.ce					(ce_28m),
	.resetbtn_n			(btn_reset_n),
	.resetgsbtn_n		(btn_reset_gs_n),
	.locked				(locked),
	.clk_bus				(clk_bus),
	.f1_out				(f1),

	.sram_addr			(MA),
	.sram_data			(MD),
	.sram_we_n			(MWR_N),
	.sram_rd_n			(MRD_N),

	.VGA_R				(video_r),
	.VGA_G				(video_g),
	.VGA_B				(video_b),
	.VGA_HS				(video_hsync),
	.VGA_VS				(video_vsync),
	.VGA_BLANK			(video_blank),

	.beep					(audio_beeper),
	.audio_out_l		(audio_out_l),
	.audio_out_r		(audio_out_r),

`ifdef HW_ID2
	.adc_in_l			(adc_l[23:8]),
	.adc_in_r			(adc_r[23:8]),
`endif

`ifdef HW_ID3
	.esp_in_l         (esp_l[15:0]),
	.esp_in_r         (esp_r[15:0]),
`endif

	.sdcs_n				(SD_CS_N),
	.sdclk				(SD_CLK),
	.sddo					(SD_DI),
	.sddi					(SD_DO),

	.ftcs_n				(ftcs_n),
	.espcs_n          (espcs_n),
	.ftclk				(ftclk),
	.ftdo					(ftdo),
	.ftdi					(ftdi),
	.ftint				(ftint),
	.vdac2_sel			(vdac2_sel),

	.joy_data			(joy_bus),

	.mouse_addr			(mouse_addr),
	.mouse_data			(mouse_data),

	.keyboard_addr		(keyboard_addr),
	.keyboard_data		(keyboard_data),
	.keyboard_scancode(keyboard_scancode),

	.rtc_addr			(rtc_addr),
	.rtc_di				(rtc_di),
	.rtc_do				(rtc_do_mapped),
	.rtc_wr				(rtc_wr),
	.rtc_rd				(rtc_rd),

	.uart_rx				(UART_RX),
	.uart_tx				(UART_TX),
	.uart_cts			(UART_CTS),

	.ide_d				(WD),
	.ide_rs_n			(WRESET_N),
	.ide_a				(WA),
	.ide_dir				(),
	.ide_cs0_n			(WCS_N[0]),
	.ide_cs1_n			(WCS_N[1]),
	.ide_rd_n			(WRD_N),
	.ide_wr_n			(WWR_N),
	.ide_rdy				(),

	.tape_in				(tape_in_r),
	.tape_out			(TAPE_OUT),

	.covox_en			(covox_en),
	.psg_mix				(psg_mix),
	.psg_type			(psg_type),
	.vga_60hz			(kb_vga_60hz),

	.loader_act			(loader_act),
	.loader_a			(loader_addr),
	.loader_d			(loader_data),
	.loader_wr			(loader_wr),

	.usb_uart_rx_data	(uart_rx_data),
	.usb_uart_rx_idx	(uart_rx_idx),
	.usb_uart_tx_data	(uart_tx_data),
	.usb_uart_tx_wr	(uart_tx_wr),
	.usb_uart_tx_mode	(uart_tx_mode),
	.usb_uart_dll		(uart_dll),
	.usb_uart_dlm		(uart_dlm),
	.usb_uart_dll_wr	(uart_dll_wr),
	.usb_uart_dlm_wr	(uart_dlm_wr),

	.sdram_clk			(SDR_CLK),
	.sdram_ba			(SDR_BA),
	.sdram_a				(SDR_A),
	.sdram_dqm			(SDR_DQM),
	.sdram_we_n			(SDR_WE_N),
	.sdram_cas_n		(SDR_CAS_N),
	.sdram_ras_n		(SDR_RAS_N),
	.sdram_dq			(SDR_DQ),

	.midi_reset_n		(),
	.midi_tx				(MIDI_TX)
 );

wire [7:0] rtc_do_mapped;

// ft control signals, mux between tsconf / mcu access
wire ftcs_n, espcs_n, ftclk, ftdo, ftdi, ftint, vdac2_sel;
wire mcu_ft_spi_on, mcu_ft_vga_on, mcu_ft_sck, mcu_ft_mosi, mcu_ft_cs_n, mcu_ft_reset;

assign FT_SPI_CS_N = mcu_ft_spi_on ? mcu_ft_cs_n : ftcs_n;
assign ESP32_SPI_CS_N = espcs_n;
assign FT_SPI_SCK = mcu_ft_spi_on ? mcu_ft_sck : ftclk;
assign ftdi = FT_SPI_MISO;
assign FT_SPI_MOSI = mcu_ft_spi_on ? mcu_ft_mosi : ftdo;
assign ftint = FT_INT_N;

// ft clk input buf
wire ft_clk_int;
IBUFG(.I(FT_CLK), .O(ft_clk_int));

// 28 / FT_CLK mux 
BUFGMUX v_clk_mux(.I0(ce_28m), .I1(ft_clk_int), .O(v_clk_int), .S(vdac2_sel));

// hdmi
wire [7:0] hdmi_freq;
zhdmi_top #(.SAMPLERATE(48000)) zhdmi_top(
	.clk				(v_clk_int),
	.clk_ref			(clk_bus),
	.clk_8			(clk_8mhz),
	.reset			(areset || kb_reset),

	.vga_rgb			({osd_r[7:0], osd_g[7:0], osd_b[7:0]}),
	.vga_hs			(video_hsync),
	.vga_vs			(video_vsync),
	.vga_de			(~video_blank),

	.ft_rgb			({VGA_R[7:0], VGA_G[7:0], VGA_B[7:0]}),
	.ft_hs			(VGA_HS),
	.ft_vs			(VGA_VS),
	.ft_de			(FT_DE),

	.ft_sel			(vdac2_sel),

	.audio_l			(audio_mix_l),
	.audio_r			(audio_mix_r),

	.tmds_p			(TMDS_P),
	.tmds_n			(TMDS_N),

	.freq				(hdmi_freq)
);

// ------- i2s DAC --------------
PCM5102 #(.DAC_CLK_DIV_BITS(2)) PCM5102(
	.clk				(clk_bus),
	.reset			(areset),
	.left				(audio_mix_l),
	.right			(audio_mix_r),
	.din				(DAC_DAT),
	.bck				(DAC_BCK),
	.lrck				(DAC_WS)
);

// ------- PCM1808 ADC ---------
wire signed [23:0] adc_l, adc_r;
wire adc_clk_int = clk_bus;

i2s_transceiver adc(
	.reset_n			(~areset),
	.mclk				(adc_clk_int),
	.sclk				(ADC_BCK),
	.ws				(ADC_LRCK),
	.sd_tx			(),
	.sd_rx			(ADC_DOUT),
	.l_data_tx		(24'b0),
	.r_data_tx		(24'b0),
	.l_data_rx		(adc_l),
	.r_data_rx		(adc_r)
);

// ------- ESP i2s receiver ----
wire signed [15:0] esp_l, esp_r;
i2s_rx i2s_rx(
	.clk				(clk_bus),
	.sclk				(ESP32_PCM_BCK),
	.rst				(areset),
	.lrclk			(ESP32_PCM_RLCK),
	.sdata			(ESP32_PCM_DAT),
	.left_chan		(esp_l),
	.right_chan		(esp_r)
);

// ------- ADC_CLK output buf
ODDR2 oddr_adc2(.Q(ADC_CLK), .C0(adc_clk_int), .C1(~adc_clk_int), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

// ------- audio mix
assign audio_mix_l = audio_out_l;
assign audio_mix_r = audio_out_r;

//---------- MCU ------------
mcu mcu(
	.CLK				(clk_bus),
	.N_RESET			(~areset),

	.MCU_MOSI		(MCU_MOSI),
	.MCU_MISO		(MCU_MISO),
	.MCU_SCK			(MCU_SCK),
	.MCU_SS			(MCU_CS_N),

	.MCU_SPI_FT_SS	(MCU_IO[3]),
	.MCU_SPI_SD2_SS(MCU_IO[2]),

	.MS_X				(ms_x),
	.MS_Y				(ms_y),
	.MS_Z				(ms_z),
	.MS_B				(ms_b),
	.MS_UPD			(ms_upd),

	.KB_STATUS		(hid_kb_status),
	.KB_DAT0			(hid_kb_dat0),
	.KB_DAT1			(hid_kb_dat1),
	.KB_DAT2			(hid_kb_dat2),
	.KB_DAT3			(hid_kb_dat3),
	.KB_DAT4			(hid_kb_dat4),
	.KB_DAT5			(hid_kb_dat5),

	.KB_SCANCODE	(ps2_scancode),
	.KB_SCANCODE_UPD(ps2_scancode_upd),

	.XT_SCANCODE	(),
	.XT_SCANCODE_UPD(),

	.JOY_L			(joy_l),
	.JOY_R			(joy_r),

	.RTC_A			(rtc_addr),
	.RTC_DI			(rtc_di),
	.RTC_DO			(rtc_do),
	.RTC_CS			(1'b1),
	.RTC_WR_N		(~rtc_wr),

	.UART_RX_DATA	(uart_rx_data),
	.UART_RX_IDX	(uart_rx_idx),	 
	.UART_TX_DATA	(uart_tx_data),
	.UART_TX_WR		(uart_tx_wr),

	.UART_TX_MODE	(uart_tx_mode),
	.UART_DLL		(uart_dll),
	.UART_DLM		(uart_dlm),
	.UART_DLL_WR	(uart_dll_wr),
	.UART_DLM_WR	(uart_dlm_wr),

	.ROMLOADER_ACTIVE(loader_act),
	.ROMLOAD_ADDR	(loader_addr),
	.ROMLOAD_DATA	(loader_data),
	.ROMLOAD_WR		(loader_wr),

	.SOFTSW_COMMAND(softsw_command),	
	.OSD_COMMAND	(osd_command),

	.FT_SPI_ON		(mcu_ft_spi_on),
	.FT_VGA_ON		(mcu_ft_vga_on),
	.FT_SCK			(mcu_ft_sck),
	.FT_MISO			(FT_SPI_MISO),
	.FT_MOSI			(mcu_ft_mosi),
	.FT_CS_N			(mcu_ft_cs_n),
	.FT_RESET		(mcu_ft_reset),

	.DEBUG_ADDR		(16'd0),
	.DEBUG_DATA		(16'd0),

	.BUSY				(mcu_busy)
);

//---------- Keyboard parser ------------

hid_parser hid_parser(
	.CLK				(clk_bus),
	.RESET			(areset),

	.KB_STATUS		(hid_kb_status),
	.KB_DAT0			(hid_kb_dat0),
	.KB_DAT1			(hid_kb_dat1),
	.KB_DAT2			(hid_kb_dat2),
	.KB_DAT3			(hid_kb_dat3),
	.KB_DAT4			(hid_kb_dat4),
	.KB_DAT5			(hid_kb_dat5),

	.KB_SCANCODE	(ps2_scancode),
	.KB_SCANCODE_UPD(ps2_scancode_upd),

	.JOY_TYPE_L		(kb_joy_type_l),
	.JOY_TYPE_R		(kb_joy_type_r),
	.JOY_L			(joy_l),
	.JOY_R			(joy_r),

	.KB_TYPE			(1'b1),
	.A 				(keyboard_addr),

	.JOY_DO			(joy_bus),
	.KB_DO			(keyboard_data),

	.RTC_A			(rtc_addr),
	.RTC_WR			(rtc_wr),
	.RTC_RD			(rtc_rd),
	.RTC_DI			(rtc_di),
	.RTC_DO_IN		(rtc_do),
	.RTC_DO_OUT		(rtc_do_mapped)
);

//---------- Soft switches ------------

wire covox_en, psg_type;
wire [1:0] psg_mix;

soft_switches soft_switches(
	.CLK				(clk_bus),
	.SOFTSW_COMMAND(softsw_command),
	.COVOX_EN		(covox_en),
	.PSG_MIX			(psg_mix),
	.PSG_TYPE		(psg_type),
	.JOY_TYPE_L		(kb_joy_type_l),
	.JOY_TYPE_R		(kb_joy_type_r),
	.VGA_60HZ		(kb_vga_60hz),
	.PAUSE			(kb_pause),
	.RESET_GS		(kb_reset_gs),
	.NMI				(kb_nmi),
	.RESET			(kb_reset)
);

assign btn_reset_n = ~kb_reset & ~mcu_busy;
assign btn_reset_gs_n = ~kb_reset_gs & ~mcu_busy;

//---------- Mouse / cursor ------------

wire [7:0] ms_x, ms_y, cursor_x, cursor_y;
wire [3:0] ms_z, cursor_z;
wire [2:0] ms_b, cursor_b;
wire ms_upd;

cursor cursor(
	.CLK				(clk_bus),
	.RESET			(areset),

	.MS_X				(ms_x),
	.MS_Y				(ms_y),
	.MS_Z				(ms_z),
	.MS_B				(ms_b),
	.MS_UPD			(ms_upd),

	.OUT_X			(cursor_x),
	.OUT_Y			(cursor_y),
	.OUT_Z			(cursor_z),
	.OUT_B			(cursor_b)
);

always @* begin
	casex (mouse_addr)
		3'bX10:	mouse_data	<= {cursor_z[3:0], 1'b1, ~cursor_b[2:0]};
		3'b011:	mouse_data	<= cursor_x;
		3'b111:	mouse_data	<= cursor_y;
		default:	mouse_data	<= 8'hFF;
	endcase
end

//--------- OSD --------------

overlay overlay(
	.CLK				(clk_bus),
	.RGB_I			({video_r[7:0], video_g[7:0], video_b[7:0]}),
	.RGB_O			({osd_r[7:0], osd_g[7:0], osd_b[7:0]}),
	.HSYNC_I			(video_hsync),
	.VSYNC_I			(video_vsync),
	.OSD_COMMAND	(osd_command)
);

endmodule
