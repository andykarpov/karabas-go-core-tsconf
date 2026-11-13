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
-- FPGA TS-Conf core for Karabas-Go
--
-- @author Andy Karpov <andy.karpov@gmail.com>
-- @author Oleh Starychenko <solegstar@gmail.com>
-- Ukraine, 2023
------------------------------------------------------------------------------------------------------------------*/

module karabas_go_top (
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
   output wire [7:0] VGA_R,
   output wire [7:0] VGA_G,
   output wire [7:0] VGA_B,
   output wire VGA_HS,
   output wire VGA_VS,
	output wire V_CLK,
	
	//---------------------------
	output wire FT_SPI_CS_N,
	output wire FT_SPI_SCK,
	input wire FT_SPI_MISO,
	output wire FT_SPI_MOSI,
	input wire FT_INT_N,
	input wire FT_CLK,
	output wire FT_OE_N,

	//---------------------------
	output wire [2:0] WA,
	output wire [1:0] WCS_N,
	output wire WRD_N,
	output wire WWR_N,
	output wire WRESET_N,
	inout wire [15:0] WD,
	
	//---------------------------
	input wire FDC_INDEX,
	output wire [1:0] FDC_DRIVE,
	output wire FDC_MOTOR,
	output wire FDC_DIR,
	output wire FDC_STEP,
	output wire FDC_WDATA,
	output wire FDC_WGATE,
	input wire FDC_TR00,
	input wire FDC_WPRT,
	input wire FDC_RDATA,
	output wire FDC_SIDE_N,

   //---------------------------	
	output wire TAPE_OUT,
	input wire TAPE_IN,
	output wire BEEPER,
	
	//---------------------------
	output wire DAC_LRCK,
   output wire DAC_DAT,
   output wire DAC_BCK,
   output wire DAC_MUTE,
	
	//---------------------------
	input wire MCU_CS_N,
	input wire MCU_SCK,
	inout wire MCU_MOSI,
	output wire MCU_MISO,
	input wire MCU_SPI_FT_CS_N,
	input wire MCU_SPI_SD2_CS_N,	
	inout wire [1:0] MCU_SPI_IO,  // [0] INT of link v2 (N9), [1] unused (M11)
	
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
// karabas: made by src/tools/mktop_go.py from karabas_minig_top.v (do not edit it, change Mini G)

// unused signals yet
assign FLASH_CS_N 	= 1'b1;
assign FLASH_DI 		= 1'b1;
assign FLASH_SCK 		= 1'b0;
assign FLASH_WP_N 	= 1'b1;
assign FLASH_HOLD_N 	= 1'b1;

// system clocks
wire clk_sys, clk_8mhz, clk_bus, clk_bus_pll, clk_12mhz;
wire locked, areset;

// VCO 50 * 37 / 2 = 925 MHz, phase 0: clk_sys 84.09 MHz (/11), clk_8 7.97 MHz (/116), clk_bus 28.03 MHz (/33,
// every third edge of clk_sys), MIDI 12.01 MHz (/77). clk_bus was a BUFGCE of clk_sys with ce_28m. Its PLL output
// has no BUFG in kg_pll: it drives the BUFG of clk_bus and the BUFGMUXes of hdmi_pll (no BUFG in front of them).
wire [5:0] pll_clk;
kg_pll #(
	.DIVCLK_DIVIDE(2), .CLKFBOUT_MULT(37),
	.CLKOUT0_DIVIDE(11), .CLKOUT1_DIVIDE(116), .CLKOUT2_DIVIDE(33), .CLKOUT3_DIVIDE(77),
	.BUFG_MASK(6'b001011)
) pll (
	.clk_in			(CLK_50MHZ),
	.rst				(1'b0),
	.clk_out			(pll_clk),
	.locked			(locked)
);
assign clk_sys = pll_clk[0];
assign clk_8mhz = pll_clk[1];
assign clk_bus_pll = pll_clk[2];
assign clk_12mhz = pll_clk[3];
BUFG bufg_clk_bus(.I(clk_bus_pll), .O(clk_bus));

// the midi clock of the SAM2695 (12 MHz); the Go has no FT_CLK_OUT (the FT812 has its own crystal)
ODDR2 u_midi_clk (.Q(MIDI_CLK), .C0(clk_12mhz), .C1(~clk_12mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));

assign areset = ~locked;

// clk_sys enables of the edges of clk_bus: ce_28m for the SRAM controller, v_clk for the V_CLK pin
wire ce_28m, v_clk;
bus_ce bus_ce(.clk_sys(clk_sys), .clk_bus(clk_bus), .ce(ce_28m), .v_clk(v_clk));

// tape in reg
reg tape_in_r;
always @(posedge clk_bus)
begin
	tape_in_r <= TAPE_IN;
end

// tsconf core
wire [7:0] video_r, video_g, video_b, osd_r, osd_g, osd_b;
wire osd_hs, osd_vs, osd_de;
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
wire [2:0] kb_joy_type_l, kb_joy_type_r;
wire kb_vga_60hz;
wire [7:0] joy_bus;
wire kb_pause, kb_reset, kb_reset_gs, kb_nmi, mcu_busy;
reg nmi_n = 1'b1;
wire f1;
wire [7:0] hwid;
wire dvi_only;
wire [1:0] hw_btn;
wire [23:0] matrix_cmd;
wire matrix_cmd_wr;
wire iowr;
wire [25:0] ioa;
wire [7:0] iod;

tsconf tsconf (
	.clk					(clk_sys),
	.clk8					(clk_8mhz),
	.ce					(ce_28m),
	.resetbtn_n			(btn_reset_n),
	.resetgsbtn_n		(btn_reset_gs_n),
	.nmi_n				(nmi_n),
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
	.espcs_in			(espcs_in),
	.esp_ft_spi_dis	(esp_ft_spi_dis),	
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

	// the floppy connector of the Go (the physical drive of the FDC of tsconf)
	.fdc_side			(FDC_SIDE_N),
	.fdc_rdata			(FDC_RDATA),
	.fdc_wprt			(FDC_WPRT),
	.fdc_tr00			(FDC_TR00),
	.fdc_index			(FDC_INDEX),
	.fdc_wg				(FDC_WGATE),
	.fdc_wr_data		(FDC_WDATA),
	.fdc_step			(FDC_STEP),
	.fdc_dir				(FDC_DIR),
	.fdc_motor			(FDC_MOTOR),
	.fdc_ds				(FDC_DRIVE),

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

	.midi_reset_n		(MIDI_RESET_N),
	.midi_tx				(MIDI_TX),
	
    .iowr               (iowr),
    .ioa                (ioa),
    .iod                (iod)
 );

wire [7:0] rtc_do_mapped;

// ft control signals, mux between tsconf / mcu access
wire ftcs_n, espcs_n, espcs_in, esp_ft_spi_dis, ftclk, ftdo, ftdi, ftint, vdac2_sel;
wire mcu_ft_spi_on, mcu_ft_vga_on, mcu_ft_sck, mcu_ft_mosi, mcu_ft_cs_n, mcu_ft_reset;

// MCU_SCK is not on a clock pin on the Go (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)
wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;


assign espcs_in = 1'b1;
assign ESP_RESET_N = 1'bZ;
assign ESP_BOOT_N = 1'bZ;
assign BEEPER = audio_beeper;
assign FT_SPI_CS_N = esp_ft_spi_dis ? 1'bZ : (mcu_ft_spi_on ? mcu_ft_cs_n : ftcs_n);
assign FT_SPI_SCK = esp_ft_spi_dis ? 1'bZ : (mcu_ft_spi_on ? mcu_sck_ibufg : ftclk);
assign ftdi = FT_SPI_MISO;
assign FT_SPI_MOSI = esp_ft_spi_dis ? 1'bZ : (mcu_ft_spi_on ? mcu_ft_mosi : ftdo);
assign ftint = FT_INT_N;
assign FT_OE_N = esp_ft_spi_dis ? 1'b0 : (mcu_ft_vga_on ? 1'b0 : ~vdac2_sel);

// the FT812 and the FPGA share the video DAC: the FT812 drives it when the core (vdac2_sel) or the
// firmware (FT_VGA_ON) asks for it
wire ft_video_active = vdac2_sel | mcu_ft_vga_on;
assign VGA_R[7:0] = ft_video_active ? 8'bZZZZZZZZ : osd_r[7:0];
assign VGA_G[7:0] = ft_video_active ? 8'bZZZZZZZZ : osd_g[7:0];
assign VGA_B[7:0] = ft_video_active ? 8'bZZZZZZZZ : osd_b[7:0];
assign VGA_HS = ft_video_active ? 1'bZ : osd_hs;   // the syncs of the overlay: in step with osd_rgb
assign VGA_VS = ft_video_active ? 1'bZ : osd_vs;
assign V_CLK = ft_video_active ? FT_CLK : v_clk;

// ------- i2s DAC --------------
kg_pcm5102 #(.DIV_BITS(1)) PCM5102(
	.clk				(clk_bus),
	.reset			(areset),
	.left				(audio_mix_l),
	.right			(audio_mix_r),
	.din				(DAC_DAT),
	.bck				(DAC_BCK),
	.lrck				(DAC_LRCK)
);
assign DAC_MUTE = 1'b1; // soft mute, 0 = mute, 1 = unmute

// ------- audio mix
assign audio_mix_l = audio_out_l;
assign audio_mix_r = audio_out_r;

//---------- MCU ------------
// MCU link v2 (karabas-go-firmware docs/link_v2.md): kg_mcu2, the interrupt to the mcu on IO1
wire mcu_int;
assign MCU_SPI_IO[0] = mcu_int;   // INT of link v2 on N9 (IO1 of the firmware)
assign MCU_SPI_IO[1] = 1'bz;

wire [7:0] ms_x, ms_y, cursor_x, cursor_y;
wire [3:0] ms_z, cursor_z;
wire [2:0] ms_b, cursor_b;
wire ms_upd;
wire [55:0] mcu_kbd;
wire [7:0] mcu_ps2_code;
wire mcu_ps2_kind, mcu_ps2_wr;
wire [7:0] mcu_ms_z, mcu_ms_b;
wire mcu_ms_wr;
wire [15:0] mcu_joy_l, mcu_joy_r;
wire [5:0] mcu_btns;
wire [1:0] ld_kind;
wire ld_active, ld_wr;
wire [31:0] ld_addr;
wire [7:0] ld_data;
wire [31:0] port_out_data;
wire [3:0] port_out_wr;
wire osd_wr, osd_en, osd_zoom;
wire [11:0] osd_waddr;
wire [7:0] osd_wdata;
wire [23:0] osd_fg, osd_bg;
wire [1:0] osd_alpha, osd_place;
wire [4:0] osd_px, osd_ph;
wire [3:0] osd_py;
wire [5:0] osd_pw;
wire [10*8-1:0] softsw;

// the EVO RS232 divisor of the core (tx_mode 1) to the mcu in the config of port 0 (0 = 115200)
wire [127:0] port_cfg = { 96'd0, 16'd0, uart_tx_mode ? { uart_dlm, uart_dll } : 16'd0 };

kg_mcu2 #(
	.CAPS(16'h0000),
	.SW_N(10),
	.CS_FILTER(3),
	.ENABLE_OSD(1),
	.ENABLE_IMG(0),
	.ENABLE_PORTS(4'b0001),
	.ENABLE_RTC(1),
	.RTC_SKIP_0D(0),
	.RTC_SEND_LIMIT(8'hF0),
	.ENABLE_AUX(1),
	.ENABLE_FT(1),
	.ENABLE_SD2(0)
) mcu(
	.CLK				(clk_bus),
	.N_RESET			(~areset),

	.MCU_SCK			(mcu_sck),
	.MCU_MOSI		(MCU_MOSI),
	.MCU_MISO		(MCU_MISO),
	.MCU_SS			(MCU_CS_N),
	.MCU_INT			(mcu_int),
	.MCU_SPI_FT_SS	(MCU_SPI_FT_CS_N),
	.MCU_SPI_SD2_SS(1'b1),

	.SW				(softsw),
	.SW_WR			(),
	.SW_INDEX		(),
	.SW_VALUE		(),
	.HW_ID			(hwid),
	.DVI_ONLY		(dvi_only),
	.CORE_BUILD		(),
	.FW_BUILD		(),
	.BUSY				(mcu_busy),
	.BTNS				(mcu_btns),
	.RELOAD_REQ		(1'b0),
	.RELOAD_CORE	(8'd0),

	.KBD				(mcu_kbd),
	.KBD_WR			(),
	.PS2_CODE		(mcu_ps2_code),
	.PS2_KIND		(mcu_ps2_kind),
	.PS2_WR			(mcu_ps2_wr),
	.MS_X				(ms_x),
	.MS_Y				(ms_y),
	.MS_Z				(mcu_ms_z),
	.MS_B				(mcu_ms_b),
	.MS_WR			(mcu_ms_wr),
	.JOY_L			(mcu_joy_l),
	.JOY_R			(mcu_joy_r),
	.JOY_WR			(),
	.PS2_CMD			(16'h0000),
	.PS2_CMD_WR		(1'b0),

	.LD_KIND			(ld_kind),
	.LD_SLOT			(),
	.LD_SIZE			(),
	.LD_START		(),
	.LD_ACTIVE		(ld_active),
	.LD_END			(),
	.LD_ADDR			(ld_addr),
	.LD_DATA			(ld_data),
	.LD_WR			(ld_wr),
	.LD_READY		(1'b1),

	.OSD_WR			(osd_wr),
	.OSD_WADDR		(osd_waddr),
	.OSD_WDATA		(osd_wdata),
	.OSD_EN			(osd_en),
	.OSD_FG			(osd_fg),
	.OSD_BG			(osd_bg),
	.OSD_ALPHA		(osd_alpha),
	.OSD_PX			(osd_px),
	.OSD_PY			(osd_py),
	.OSD_PW			(osd_pw),
	.OSD_PH			(osd_ph),
	.OSD_PLACE		(osd_place),
	.OSD_ZOOM		(osd_zoom),

	.SDC_IMG_MOUNTED(),
	.SDC_IMG_SIZE	(),
	.SDC_RD			(8'd0),
	.SDC_WR			(8'd0),
	.SDC_SECTOR		(32'd0),
	.SDC_BUSY		(),
	.SDC_DONE		(),
	.SDC_ERROR		(),
	.SDC_SLOT		(),
	.SDC_BYTE_IN_STROBE(),
	.SDC_BYTE_ADDR	(),
	.SDC_BYTE_IN_DATA(),
	.SDC_BYTE_OUT_DATA(8'd0),
	.IMG_WP			(),
	.IMG_PHYS_WR	(),
	.IMG_PHYS		(),
	.IMG_FLUSH		(),
	.FDD_CHNG_WR	(),
	.FDD_CHNG		(),
	.FDD_CHNG_REQ	(1'b0),
	.FDD_CHNG_DS	(2'd0),
	.IMG_ACTIVE		(),

	.PORT_OUT_DATA	(port_out_data),
	.PORT_OUT_WR	(port_out_wr),
	.PORT_OUT_READY(4'b1111),
	.PORT_IN_DATA	({ 24'd0, uart_tx_data }),
	.PORT_IN_WR		({ 3'b000, uart_tx_wr }),
	.PORT_CFG		(port_cfg),
	.PORT_IN_FULL	(),
	.PORT_STAT		(),
	.PORT_STAT_WR	(),

	.RTC_A			(rtc_addr),
	.RTC_DI			(rtc_di),
	.RTC_CS			(1'b1),
	.RTC_WR_N		(~rtc_wr),
	.MATRIX_CMD		(matrix_cmd),
	.MATRIX_CMD_WR	(matrix_cmd_wr),
	.DEBUG_ADDR		(16'd0),
	.DEBUG_DATA		(16'd0),
	.RTC_DO			(rtc_do),

	.FT_SPI_ON		(mcu_ft_spi_on),
	.FT_VGA_ON		(mcu_ft_vga_on),
	.FT_RESET		(mcu_ft_reset),
	.FT_SCK			(mcu_ft_sck),
	.FT_MOSI			(mcu_ft_mosi),
	.FT_MISO			(FT_SPI_MISO),
	.FT_CS_N			(mcu_ft_cs_n),
	.SD2_SCK			(),
	.SD2_MOSI		(),
	.SD2_MISO		(1'b1),
	.SD2_CS_N		()
);

assign { hid_kb_dat5, hid_kb_dat4, hid_kb_dat3, hid_kb_dat2, hid_kb_dat1, hid_kb_dat0, hid_kb_status } = mcu_kbd;
assign joy_l = mcu_joy_l[12:0];
assign joy_r = mcu_joy_r[12:0];
assign hw_btn = mcu_btns[1:0];
assign ms_z = mcu_ms_z[3:0];
assign ms_b = mcu_ms_b[2:0];

// the ROMs of the core file (LD kind 0)
assign loader_act = ld_active && ld_kind == 2'd0;
assign loader_wr = ld_wr && ld_kind == 2'd0;
assign loader_addr = ld_addr;
assign loader_data = ld_data;

// the toggles of v1 for the PS/2 scancode (set 2) and the mouse; the USB serial port of v1: a byte and
// a counter that changes with it
reg ps2_upd_t = 1'b0, ms_upd_t = 1'b0;
reg [7:0] ps2_code_r = 8'd0, uart_rx_data_r = 8'd0, uart_rx_idx_r = 8'd0;
always @(posedge clk_bus) begin
	if (mcu_ps2_wr && !mcu_ps2_kind) begin
		ps2_code_r <= mcu_ps2_code;
		ps2_upd_t <= ~ps2_upd_t;
	end
	if (mcu_ms_wr)
		ms_upd_t <= ~ms_upd_t;
	if (port_out_wr[0]) begin
		uart_rx_data_r <= port_out_data[7:0];
		uart_rx_idx_r <= uart_rx_idx_r + 1'b1;
	end
end
assign ps2_scancode = ps2_code_r;
assign ps2_scancode_upd = ps2_upd_t;
assign ms_upd = ms_upd_t;
assign uart_rx_data = uart_rx_data_r;
assign uart_rx_idx = uart_rx_idx_r;

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

// OSD switches (core.json "osd", in this order): switch n = SW[n*8 +: 8] of kg_mcu2

assign covox_en = softsw[0];
assign psg_mix = softsw[9:8];
assign psg_type = softsw[16];
assign kb_joy_type_l = softsw[26:24];
assign kb_joy_type_r = softsw[34:32];
assign kb_vga_60hz = softsw[40];
assign kb_pause = softsw[48];
assign kb_reset_gs = softsw[56];
assign kb_nmi = softsw[64];
assign kb_reset = softsw[72];

assign btn_reset_n = ~kb_reset && ~hw_btn[0] && ~mcu_busy;
assign btn_reset_gs_n = ~kb_reset_gs & ~mcu_busy;

// NMI of the Z80: the OSD item (F11) or BTN2, registered (T80 takes the falling edge: one NMI per press)
always @(posedge clk_bus)
	nmi_n <= ~(kb_nmi | hw_btn[1]);

//---------- Mouse / cursor ------------


kg_cursor #(.Z_W(4), .Z_NEG(1), .Z_ACC(1)) cursor(
	.clk				(clk_bus),
	.ms_x				(ms_x),
	.ms_y				(ms_y),
	.ms_z				(ms_z),
	.ms_b				(ms_b),
	.ms_upd			(ms_upd),
	.x					(cursor_x),
	.y					(cursor_y),
	.z					(cursor_z),
	.b					(cursor_b)
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

kg_l2_osd_overlay overlay(
	.wclk				(clk_bus),
	.osd_wr			(osd_wr),
	.osd_waddr		(osd_waddr),
	.osd_wdata		(osd_wdata),
	.osd_en			(osd_en),
	.osd_fg			(osd_fg),
	.osd_bg			(osd_bg),
	.osd_alpha		(osd_alpha),
	.osd_px			(osd_px),
	.osd_py			(osd_py),
	.osd_pw			(osd_pw),
	.osd_ph			(osd_ph),
	.osd_place		(osd_place),
	.osd_zoom		(osd_zoom),
	.icon_on			(8'd0),
	.icon_act		(8'd0),

	.clk				(clk_bus),
	.rgb_i			({video_r[7:0], video_g[7:0], video_b[7:0]}),
	.hs_i				(video_hsync),
	.vs_i				(video_vsync),
	.de_i				(~video_blank),
	.rgb_o			({osd_r[7:0], osd_g[7:0], osd_b[7:0]}),
	.hs_o				(osd_hs),
	.vs_o				(osd_vs),
	.de_o				(osd_de)
);

// --------- Dot Matrix --------

// no dot matrix on the Go: MATRIX_CMD of kg_mcu2 stays 0
assign matrix_cmd = 24'd0;
assign matrix_cmd_wr = 1'b0;


endmodule
