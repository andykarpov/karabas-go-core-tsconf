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
	output wire MCU_MISO	
   );

	// todo: esp control
	assign ESP_RESET_N = 1'bZ;
	assign ESP_BOOT_N = 1'bZ;	
	
	assign BEEPER = audio_beeper;
	
	wire clk_sys;
	wire clk_8mhz;
	wire clk_bus;
	wire clk_16mhz;
   wire locked;
	wire areset;
   pll pll (
	  .CLK_IN1(CLK_50MHZ),
	  .CLK_OUT1(clk_sys),
	  .CLK_OUT2(clk_8mhz),
	  .CLK_OUT3(clk_16mhz),
	  .LOCKED(locked)
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
	wire btn_reset_n;
	wire audio_beeper;
	wire [15:0] audio_out_l;
	wire [15:0] audio_out_r;
	wire [11:0] joy_l;
	wire [11:0] joy_r;
	wire [11:0] joy_usb;
	wire [2:0] mouse_addr;
	reg [7:0] mouse_data;
	wire [15:8] keyboard_addr;
	wire [4:0] keyboard_data;
	wire [7:0] keyboard_scancode;
	wire [7:0] rtc_addr;
	wire [7:0] rtc_di;
	wire [7:0] rtc_do;
	wire rtc_wr;
	wire [7:0] uart_rx_data;
	wire [7:0] uart_rx_idx;
	wire [7:0] uart_tx_data;
	wire uart_tx_wr;
	wire [7:0] hid_kb_status;
	wire [7:0] hid_kb_dat0;
	wire [7:0] hid_kb_dat1;
	wire [7:0] hid_kb_dat2;
	wire [7:0] hid_kb_dat3;
	wire [7:0] hid_kb_dat4;
	wire [7:0] hid_kb_dat5;
	wire loader_act;
	wire [31:0] loader_addr;
	wire [7:0] loader_data;
	wire loader_wr;
	wire [15:0] softsw_command;
	wire [15:0] osd_command;
	wire [2:0] kb_joy_type_l;
	wire [2:0] kb_joy_type_r;
	wire [7:0] joy_bus;
	wire kb_pause;
	wire kb_reset;
	wire kb_nmi;
	wire mcu_busy;
	wire f1;

	tsconf tsconf (
     .clk(clk_sys),
	  .clk8(clk_8mhz),
	  .ce(ce_28m),
	  .resetbtn_n(btn_reset_n),	  
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
	  
	  .clk_16(clk_16mhz),
	  .fdc_side(FDC_SIDE_N),
	  .fdc_rdata(FDC_RDATA),
	  .fdc_wprt(FDC_WPRT),
	  .fdc_tr00(FDC_TR00),
	  .fdc_index(FDC_INDEX),
	  .fdc_wg(FDC_WGATE),
	  .fdc_wr_data(FDC_WDATA),
	  .fdc_step(FDC_STEP),
	  .fdc_dir(FDC_DIR),
	  .fdc_motor(FDC_MOTOR),
	  .fdc_ds(FDC_DRIVE),
	  
	  .loader_act(loader_act),
	  .loader_a(loader_addr),
	  .loader_d(loader_data),
	  .loader_wr(loader_wr),
	  
	  .usb_uart_rx_data(uart_rx_data),
	  .usb_uart_rx_idx(uart_rx_idx),	 
	  .usb_uart_tx_data(uart_tx_data),
	  .usb_uart_tx_wr(uart_tx_wr),	  

		.sdram_clk(SDR_CLK),
      .sdram_ba(SDR_BA),
      .sdram_a(SDR_A),
      .sdram_dqm(SDR_DQM),
      .sdram_we_n(SDR_WE_N),
      .sdram_cas_n(SDR_CAS_N),
      .sdram_ras_n(SDR_RAS_N),
      .sdram_dq(SDR_DQ)		
	  
	 );
	 
wire [7:0] rtc_do_mapped;
assign rtc_do_mapped = (rtc_addr == 8'hF0 ? keyboard_scancode : (rtc_addr == 8'h0D ? 8'b10000000 : rtc_do));
	 
wire ftcs_n, ftclk, ftdo, ftdi, ftint, vdac2_sel;

assign VGA_R[7:0] = (vdac2_sel ? 8'bZZZZZZZZ : osd_r[7:0]);
assign VGA_G[7:0] = (vdac2_sel ? 8'bZZZZZZZZ : osd_g[7:0]);
assign VGA_B[7:0] = (vdac2_sel ? 8'bZZZZZZZZ : osd_b[7:0]);
assign VGA_HS = (vdac2_sel ? 1'bZ : video_hsync);
assign VGA_VS = (vdac2_sel ? 1'bZ : video_vsync);
assign V_CLK = (vdac2_sel ? FT_CLK : ce_28m);
assign FT_SPI_CS_N = ftcs_n;
assign FT_SPI_SCK = ftclk;
assign FT_OE_N = (vdac2_sel ? 1'b0 : 1'b1);
assign ftdi = FT_SPI_MISO;
assign FT_SPI_MOSI = ftdo;
assign ftint = FT_INT_N;

//---------- MCU ------------

mcu mcu(
	.CLK(clk_bus),
	.N_RESET(~areset),
	
	.MCU_MOSI(MCU_MOSI),
	.MCU_MISO(MCU_MISO),
	.MCU_SCK(MCU_SCK),
	.MCU_SS(MCU_CS_N),
	
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
	
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	.JOY_USB(joy_usb),
	
	.RTC_A(rtc_addr),
	.RTC_DI(rtc_di),
	.RTC_DO(rtc_do),
	.RTC_CS(1'b1),
	.RTC_WR_N(~rtc_wr),
	
	.UART_RX_DATA(uart_rx_data),
	.UART_RX_IDX(uart_rx_idx),	 
	.UART_TX_DATA(uart_tx_data),
	.UART_TX_WR(uart_tx_wr),
	
	.ROMLOADER_ACTIVE(loader_act),
	.ROMLOAD_ADDR(loader_addr),
	.ROMLOAD_DATA(loader_data),
	.ROMLOAD_WR(loader_wr),
	
	.SOFTSW_COMMAND(softsw_command),	
	.OSD_COMMAND(osd_command),
	
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

	.JOY_TYPE_L(kb_joy_type_l),
	.JOY_TYPE_R(kb_joy_type_r),
	.JOY_L(joy_l),
	.JOY_R(joy_r),
	
	.KB_TYPE(1'b1),
	.A (keyboard_addr),	
	
	.JOY_DO(joy_bus),
	.KB_DO(keyboard_data),
	.KEYCODE(keyboard_scancode)
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
	.PAUSE(kb_pause),
	.NMI(kb_nmi),
	.RESET(kb_reset)
);

assign btn_reset_n = ~kb_reset & ~mcu_busy;

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

//---------- DAC ------------

PCM5102 PCM5102(
	.clk(clk_bus),
	.left(audio_out_l),
	.right(audio_out_r),
	.din(DAC_DAT),
	.bck(DAC_BCK),
	.lrck(DAC_LRCK)
);
assign DAC_MUTE = 1'b1; // soft mute, 0 = mute, 1 = unmute

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
