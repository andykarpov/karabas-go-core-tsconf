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
-- EU, 2024-2025
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
	output wire FT_8MHZ,

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
	input wire [3:0] MCU_IO,
	
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
	wire v_clk_int;
	wire p_clk_int, p_clk_div2;
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
	reg [3:0] pll_rst_cnt = 4'd0;
	wire pll_rst;
	/*
	wire clkfbout, clkfbin;
	PLL_BASE #(
		 .CLKIN_PERIOD(13.0),
		 .CLKFBOUT_MULT(20),
		 .CLKOUT0_DIVIDE(4),
		 .CLKOUT1_DIVIDE(4),
		 .CLKOUT1_PHASE(180.0),
		 .CLKOUT2_DIVIDE(20),
		 .CLKOUT3_DIVIDE(40),
		 .COMPENSATION("INTERNAL"), // default: SYSTEM_SYNCHRONOUS. try: INTERNAL, SOURCE_SYNCHRONOUS
		 .BANDWIDTH("LOW"),
		 .REF_JITTER(0.200)
	  ) pllx5 
	  (
		.CLKIN(v_clk_int),
		.CLKFBIN(clkfbin),
		.CLKFBOUT(clkfbout),
		.RST(pll_rst),
		.LOCKED(lockedx5),
		.CLKOUT0(clkfx), // 5x
		.CLKOUT1(clkfx180), // 5x 180deg
		.CLKOUT2(clk0), // 1x
		.CLKOUT3(clkdv) // div2
	  );
	  
  // this buf is needed in order to deskew between PLL clkin and clkout
  // so 2x and 10x clock will have the same phase as input clock
  //BUFG clkfb_buf (.I(clkfbout), .O(clkfbin));	
  assign clkfbin = clkfbout; // internal compensation should be directly connected
	 
  BUFG clkout1_buf (.O(clk_hdmi), .I(clkfx));
  BUFG clkout2_buf (.O(clk_hdmi_n), .I(clkfx180));
  BUFG clkout3_buf (.O(p_clk_int), .I(clk0));
  BUFG clkout4_buf (.O(p_clk_div2), .I(clkdv));
  */
  
  wire clk_hdmi_valid;
  
  hdmi_pll hdmi_pll(
	.RST(1'b0),
	.SSTEP(pll_rst),
	.CLKDRP(clk_bus),
	.FREQ(hdmi_freq),
	.CLKIN(v_clk_int),
	.CLKIN_RDY_N(locked),
	.CLK0OUT(clk_hdmi),
	.CLK1OUT(clk_hdmi_n),
	.CLK2OUT(p_clk_int),
	.VALID(clk_hdmi_valid)
  );
  
  assign lockedx5 = ~clk_hdmi_valid;
	
  always @(posedge clk_bus)
  begin
	if (kb_reset || areset || hdmi_reset) begin
		pll_rst_cnt <= 4'b1000;
	end
	if (pll_rst_cnt > 0) pll_rst_cnt <= pll_rst_cnt+1;
  end
  assign pll_rst = pll_rst_cnt[3];
  
  // TODO: DCM_CLKGEN with 8mhz input and ft_clk_int output

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
	
	// ft 8mhz
	ODDR2 u_ft_8mhz (
		.Q(FT_8MHZ),
		.C0(clk_8mhz),
		.C1(~clk_8mhz),
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

// grab FT rgb and sync into p_clk_int registers on negedge
reg ft_vga_hs_r, ft_vga_vs_r, ft_vga_blank_r, ft_vga_hs_r2, ft_vga_vs_r2, ft_vga_blank_r2;
reg [7:0] ft_vga_r_r, ft_vga_g_r, ft_vga_b_r, ft_vga_r_r2, ft_vga_g_r2, ft_vga_b_r2;
always @(negedge p_clk_int)
begin
	ft_vga_hs_r <= VGA_HS; 				ft_vga_hs_r2 <= ft_vga_hs_r;
	ft_vga_vs_r <= VGA_VS; 				ft_vga_vs_r2 <= ft_vga_vs_r;
	ft_vga_blank_r <= ~FT_DE;  		ft_vga_blank_r2  <= ft_vga_blank_r;
	ft_vga_r_r <= VGA_R;    			ft_vga_r_r2 <= ft_vga_r_r;
	ft_vga_g_r <= VGA_G;    			ft_vga_g_r2 <= ft_vga_g_r;
	ft_vga_b_r <= VGA_B;    			ft_vga_b_r2 <= ft_vga_b_r;
end

// 2-port ram for 2-lines of rgb + hs + vs + de
/*wire ft_vga_hs_r2, ft_vga_vs_r2, ft_vga_blank_r2;
wire [7:0] ft_vga_r_r2, ft_vga_g_r2, ft_vga_b_r2;
reg [11:0] ft_rd_addr, ft_wr_addr;
reg ft_wr_line, ft_rd_line;
reg [11:0] line_width, line_width_cnt;
reg prev_ft_de;
reg prev_ft_wr_line;

ft_ram ft_ram(
  .clka(FT_CLK),
  .wea({1'b1}),
  .addra({ft_wr_line, ft_wr_addr[10:0]}),
  .dina({VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, ~FT_DE}),
  .clkb(p_clk_int),
  .addrb({ft_rd_line, ft_rd_addr[10:0]}),
  .doutb({ft_vga_r_r2, ft_vga_g_r2, ft_vga_b_r2, ft_vga_hs_r2, ft_vga_vs_r2, ft_vga_blank_r2})
);

// detect line_width 
// start of line / rd / wr address
always @(FT_CLK)
begin
	if (~prev_ft_de && FT_DE)
	begin
		ft_wr_line <= ~ft_wr_line;
		ft_wr_addr <= 12'b0;
		line_width_cnt <= 12'b0;
	end
	else if (prev_ft_de && ~FT_DE)
	begin
		line_width <= line_width_cnt;
	end
	else
	begin
		if (FT_DE) line_width_cnt <= line_width_cnt + 1;
		ft_wr_addr <= ft_wr_addr + 1;
	end
	prev_ft_de <= FT_DE;
end

always @(p_clk_int)
begin
	if (prev_ft_wr_line != ft_wr_line) 
	begin
		ft_rd_line <= ~ft_wr_line;
		ft_rd_addr <= 11'b0;
	end
	else
		ft_rd_addr <= ft_rd_addr + 1;
	prev_ft_wr_line <= ft_wr_line;	
end*/

// fifo between ft_clk and p_clk signals
/*wire ft_vga_hs_r2, ft_vga_vs_r2, ft_vga_blank_r2;
wire [7:0] ft_vga_r_r2, ft_vga_g_r2, ft_vga_b_r2;

ft_fifo ft_fifo(
  .rst(areset || pll_rst),
  .wr_clk(FT_CLK),
  .rd_clk(p_clk_int),
  .din({VGA_R, VGA_G, VGA_B, VGA_HS, VGA_VS, ~FT_DE}),
  .wr_en(1'b1),
  .rd_en(1'b1),
  .dout({ft_vga_r_r2, ft_vga_g_r2, ft_vga_b_r2, ft_vga_hs_r2, ft_vga_vs_r2, ft_vga_blank_r2}),
  .full(),
  .empty()
);*/

// grab TS rgb and sync into p_clk_int registers on posedge
reg ts_vga_hs_r, ts_vga_vs_r, ts_vga_blank_r, ts_vga_hs_r2, ts_vga_vs_r2, ts_vga_blank_r2;
reg [7:0] ts_vga_r_r, ts_vga_g_r, ts_vga_b_r, ts_vga_r_r2, ts_vga_g_r2, ts_vga_b_r2;
always @(posedge p_clk_int)
begin
	ts_vga_hs_r <= video_hsync; 		ts_vga_hs_r2 <= ts_vga_hs_r;
	ts_vga_vs_r <= video_vsync; 		ts_vga_vs_r2 <= ts_vga_vs_r;
	ts_vga_blank_r <= video_blank; 	ts_vga_blank_r2  <= ts_vga_blank_r;
	ts_vga_r_r <= osd_r;    			ts_vga_r_r2 <= ts_vga_r_r;
	ts_vga_g_r <= osd_g;    			ts_vga_g_r2 <= ts_vga_g_r;
	ts_vga_b_r <= osd_b;    			ts_vga_b_r2 <= ts_vga_b_r;
end

assign host_vga_r = (vdac2_sel ? (ft_vga_blank_r2 ? 8'b0 : ft_vga_r_r2) : (ts_vga_blank_r2 ? 8'b0 : ts_vga_r_r2));
assign host_vga_g = (vdac2_sel ? (ft_vga_blank_r2 ? 8'b0 : ft_vga_g_r2) : (ts_vga_blank_r2 ? 8'b0 : ts_vga_g_r2));
assign host_vga_b = (vdac2_sel ? (ft_vga_blank_r2 ? 8'b0 : ft_vga_b_r2) : (ts_vga_blank_r2 ? 8'b0 : ts_vga_b_r2));
assign host_vga_hs = (vdac2_sel ? (ft_vga_blank_r2 ? 1'b1 :ft_vga_hs_r2) : ts_vga_hs_r2);
assign host_vga_vs = (vdac2_sel ? (ft_vga_blank_r2 ? 1'b1 :ft_vga_vs_r2) : ts_vga_vs_r2);
assign host_vga_blank = (vdac2_sel ? ft_vga_blank_r2 : ts_vga_blank_r2);

assign FT_SPI_CS_N = mcu_ft_spi_on ? mcu_ft_cs_n : ftcs_n;
assign FT_SPI_SCK = mcu_ft_spi_on ? mcu_ft_sck : ftclk;
assign ftdi = FT_SPI_MISO;
assign FT_SPI_MOSI = mcu_ft_spi_on ? mcu_ft_mosi : ftdo;
assign ftint = FT_INT_N;
assign FT_RESET = ~mcu_ft_reset; // 1'b1

// pixelclock mux
BUFGMUX v_clk_mux(
 .I0(ce_28m),
 .I1(clk_8mhz),
 .O(v_clk_int),
 .S(vdac2_sel)
);

// hdmi reset pulse when freq changes
always @(posedge clk_bus)
begin
	hdmi_reset <= 1'b0;
	if (prev_hdmi_freq != hdmi_freq) hdmi_reset <= 1'b1;
	prev_hdmi_freq <= hdmi_freq;
end

// freq counter (in Mhz)
freq_counter freq_counter_inst(
	.i_clk_ref(clk_bus),
	.i_clk_test(FT_CLK),
	.i_reset(areset),
	.o_freq(hdmi_freq)
);

// 32kHz audio samplerate
// prescaler = (clock_speed/desired_clock_speed)/2
reg clk_audio;
wire [9:0] prescaler = ((hdmi_freq * 1000000) / 32000) / 2;
reg [9:0] cnt_audio;
always @(posedge p_clk_int)
begin
		if (pll_rst || ~lockedx5) 
		begin
			cnt_audio <= 0;
			clk_audio <= 0;
		end
		else 
		begin
			if (cnt_audio > prescaler) 
			begin
				cnt_audio <= 0;
				clk_audio <= ~clk_audio;
			end
			else
				cnt_audio <= cnt_audio + 1;
		end
end

// hdmi audio (downsample with 32000 samplerate)
reg [23:0] hdmi_audio_l, hdmi_audio_r;
always @(posedge p_clk_int)
begin
	if (!clk_audio) 
	begin
		hdmi_audio_l <= {audio_mix_l[15:0], 8'b0};
		hdmi_audio_r <= {audio_mix_r[15:0], 8'b0};
	end
end

// hdmi tx
hdmi_tx hdmi_tx(
	.clk(p_clk_int),
	.sclk(clk_hdmi),
	.sclk_n(clk_hdmi_n),
	.reset(~lockedx5),
	.rgb({host_vga_r, host_vga_g, host_vga_b}),
	.vsync(host_vga_vs),
	.hsync(host_vga_hs),
	.de(~host_vga_blank),
	
	.audio_en(1'b1),
	.audio_l(hdmi_audio_l),
	.audio_r(hdmi_audio_r),
	.audio_clk(clk_audio),
	
	.tx_clk_n(TMDS_N[3]),
	.tx_clk_p(TMDS_P[3]),
	.tx_d_n(TMDS_N[2:0]),
	.tx_d_p(TMDS_P[2:0]) // 0:blue, 1:green, 2:red
);

//------- Sigma-Delta DAC ---------
dac dac_l(
	.I_CLK(clk_bus),
	.I_RESET(areset),
	.I_DATA({2'b00, !audio_mix_l[15], audio_mix_l[14:4], 2'b00}),
	.O_DAC(AUDIO_L)
);

dac dac_r(
	.I_CLK(clk_bus),
	.I_RESET(areset),
	.I_DATA({2'b00, !audio_mix_r[15], audio_mix_r[14:4], 2'b00}),
	.O_DAC(AUDIO_R)
);

// ------- PCM1808 ADC ---------
wire signed [23:0] adc_l, adc_r;

i2s_transceiver adc(
	.reset_n(~areset),
	.mclk(clk_bus),
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
	.C0(clk_bus),
	.C1(~clk_bus),
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
	.DEBUG_DATA(16'd0),
	//.DEBUG_DATA({8'd0, hdmi_freq}),
	
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
