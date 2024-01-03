`include "tune.v"


module tsconf
(
  // clocks
	input wire clk,
	input wire clk8,
	input wire ce,
	input wire resetbtn_n,
	input wire locked,
	output wire clk_bus,

   // SRAM
   output wire [20:0] sram_addr,
   inout  wire [15:0] sram_data,
   output wire [1:0] sram_we_n,
   output wire [1:0] sram_rd_n,
  
	// VGA
	output wire [7:0] VGA_R,
	output wire [7:0] VGA_G,
	output wire [7:0] VGA_B,
	output wire       VGA_HS,
	output wire       VGA_VS,
	
	// SPI SD-Card
	output wire sdcs_n,
	output wire sdclk,
	output wire sddo,
	input  wire sddi,
	
	// SPI FT812
	output wire ftcs_n,
	output wire ftclk,
	output wire ftdo,
	input wire ftdi,
	input wire ftint,
	output wire vdac2_sel,

	// digital audio
	output wire [15:0] audio_out_l,
	output wire [15:0] audio_out_r,
	output wire beep,

	// joystick
	input wire [7:0] joy_data,
	
	// mouse (mcu)
	output wire [2:0] mouse_addr,
	input wire [7:0] mouse_data,
	
	// keyboard (mcu)
	output wire[15:8] keyboard_addr,
	input wire[4:0] keyboard_data,
	input wire[7:0] keyboard_scancode,
	
	// rtc (mcu)
	output wire [7:0] rtc_addr,
	output wire [7:0] rtc_di,
	input wire [7:0] rtc_do,
	output wire rtc_wr,
	
	// uart (zifi)
	input wire uart_rx,
	output wire uart_tx,
	output wire uart_cts,
	
	// ide
	inout wire [15:0] ide_d,
	output wire ide_rs_n,
	output wire [2:0] ide_a,
	output wire ide_dir,
	output wire ide_cs0_n,
	output wire ide_cs1_n,
	output wire ide_rd_n,
	output wire ide_wr_n,
	input wire ide_rdy,
	
	// tape
	input wire tape_in,
	output wire tape_out,
	
	// osd switches
	input wire covox_en,
	input wire [1:0] psg_mix,
	input wire psg_type,
	
	// fdc
	input wire clk_16,
	output wire fdc_side,
	input wire fdc_rdata,
	input wire fdc_wprt,
	input wire fdc_tr00,
	input wire fdc_index,
	output wire fdc_wg,
	output wire fdc_wr_data,
	output wire fdc_step,
	output wire fdc_dir,
	output wire fdc_motor,
	output reg [1:0] fdc_ds
	
	// TODO: others
);

  // cpu
  wire [15:0] cpu_a_bus;
  wire [7:0]  cpu_do_bus;
  wire [7:0]  cpu_di_bus;
  wire        cpu_mreq_n;
  wire        cpu_iorq_n;
  wire        cpu_wr_n;
  wire        cpu_rd_n; 
  wire        cpu_int_n_TS;
  wire        cpu_m1_n;
  wire        cpu_rfsh_n;
    
  wire [15:0] sram_do_bus_16;

  // clock
  wire f0, f1, h0, h1, c0, c1, c2, c3;
  
  wire rst_n; 
  wire genrst;

  wire [1:0] ay_mod;
  wire dos;
  wire vdos;
  wire pre_vdos;
  wire zpos, zneg;
  wire [7:0] zports_dout;
  wire zports_dataout;
  wire porthit;
  wire [1:0] dmawpdev;
  wire [7:0] kbd_data;
  wire [2:0] kbd_data_sel;
  wire [7:0] mus_data;
  wire kbd_stb, mus_xstb, mus_ystb, mus_btnstb, kj_stb;
  wire [4:0] kbd_port_data;
  wire [4:0] kj_port_data;
  wire [7:0] mus_port_data;
  wire [7:0] wait_read,wait_write;
  wire wait_start_gluclock;
  wire wait_start_comport;
  wire wait_end;
  wire [7:0] wait_addr;
  wire [1:0] wait_status;
  wire [7:0] mc146818a_do_bus;
 
  // config signals
  wire cfg_tape_sound;
  wire cfg_floppy_swap;
  wire int_start_wtp;
  wire cfg_60hz;
  wire beeper_mux; // what is mixed to FPGA beeper output - beeper(0) or tapeout(1)
  wire tape_read;  // tapein data
  wire set_nmi;
  wire cfg_vga_on;
  wire [7:0] config0;
  assign 
  {
    cfg_tape_sound,   // bit 7
    cfg_floppy_swap,  // bit 6
    int_start_wtp,    // bit 5
    cfg_60hz,         // bit 4
    beeper_mux,       // bit 3
    tape_read,        // bit 2
    set_nmi,          // bit 1
    cfg_vga_on        // bit 0
  } = config0;

  // nmi signals
  wire gen_nmi;
  wire clr_nmi;
  wire in_nmi;

  wire [7:0] zmem_dout;
  wire zmem_dataout;
  wire [7:0] received;
  wire [7:0] tobesent;
  wire intrq,drq;
  wire vg_wrFF;
  wire zclk;// = clkz_out;

  // assign nmi_n = gen_nmi ? 1'b0 : 1'bZ;
  wire video_go;
  wire beeper_wr, covox_wr;
  wire external_port;
  wire ide_stall;

  wire rampage_wr;        // ports #10AF-#13AF
  wire [7:0] memconf;
  wire [7:0] xt_ramp[0:3];
  wire [4:0] rompg;
  wire [7:0] sysconf;

  wire [1:0] turbo = sysconf[1:0];
  wire [3:0] cacheconf;
  wire [7:0] border;
  wire int_start_lin;
  wire int_start_frm;
  wire int_start_dma;

  wire [7:0] dout_ram;
  wire [7:0] dout_ports;
  wire [7:0] im2vect;
  wire ena_ram;
  wire ena_ports;
  wire drive_ff;

  wire [15:0] dram_wd;

  wire vdos_on, vdos_off;
  wire dos_on, dos_off;

  wire [20:0] daddr;
  wire dreq;
  wire drnw;
  wire [15:0] dram_rd_r;
  wire [15:0] dram_wrdata;
  wire [1:0] dbsel;

  wire cpu_req, cpu_wrbsel, cpu_strobe, cpu_latch;
  wire [20:0] cpu_addr;
  wire [20:0] video_addr;
  wire curr_cpu;
  wire cpu_next;
  wire cpu_stall;

  wire [4:0] video_bw;
  wire video_strobe;
  wire video_next;
  wire video_pre_next;
  wire next_video;

  wire [20:0] dma_addr;
  wire [15:0] dma_wrdata;
  wire dma_req;
  wire dma_rnw;
  wire dma_next;
  wire dma_strobe;

  wire [20:0] ts_addr;
  wire ts_req;
  wire ts_pre_next;
  wire ts_next;

  wire [20:0] tm_addr;
  wire tm_req;
  wire tm_next;

  wire dbg_arb;    // DEBUG!!!

  wire border_wr;
  wire zborder_wr;
  wire zvpage_wr;
  wire vpage_wr;
  wire vconf_wr;
  wire gx_offsl_wr;
  wire gx_offsh_wr;
  wire gy_offsl_wr;
  wire gy_offsh_wr;
  wire t0x_offsl_wr;
  wire t0x_offsh_wr;
  wire t0y_offsl_wr;
  wire t0y_offsh_wr;
  wire t1x_offsl_wr;
  wire t1x_offsh_wr;
  wire t1y_offsl_wr;
  wire t1y_offsh_wr;
  wire palsel_wr;
  wire hint_beg_wr;
  wire vint_begl_wr;
  wire vint_begh_wr;
  wire tsconf_wr;
  wire tmpage_wr;
  wire t0gpage_wr;
  wire t1gpage_wr;
  wire sgpage_wr;

  wire [15:0]       zmd;
  wire [7:0]       zma;
  wire cram_we;
  wire sfile_we;
  wire regs_we;

  wire rst;
  wire m1;
  wire rfsh;
  wire zrd;
  wire zwr;
  wire iorq;
  wire iorq_s;
  // wire iorq_s2;
  wire mreq;
  wire mreq_s;
  wire rdwr;
  wire iord;
  wire iowr;
  wire iordwr;
  wire iord_s;
  wire iowr_s;
  wire iordwr_s;
  wire memrd;
  wire memwr;
  wire memrw;
  wire memrd_s;
  wire memwr_s;
  wire memrw_s;
  wire opfetch;
  wire opfetch_s;
  wire intack;

  wire [31:0] xt_page;

  wire [8:0] dmaport_wr;
  wire [4:0] fmaddr;

  wire [7:0] fddvirt;

  wire [4:0] vred_raw;
  wire [4:0] vgrn_raw;
  wire [4:0] vblu_raw;
  wire vdac_mode;
  wire vsync;
  wire hsync;

  wire [15:0] z80_ide_out;
  wire z80_ide_cs0_n;
  wire z80_ide_cs1_n;
  wire z80_ide_req;
  wire z80_ide_rnw;
  wire [15:0] dma_ide_out;
  wire dma_ide_req;
  wire dma_ide_rnw;
  wire ide_stb;
  wire ide_ready;
  wire [15:0] ide_out;

  wire [7:0] intmask;

  wire dma_act;

  wire [15:0] dma_data;
  wire [7:0] dma_wraddr;
  wire dma_cram_we;
  wire dma_sfile_we;

  wire cpu_spi_req;
  wire dma_spi_req;
  wire spi_stb;
  wire spi_start;
  wire [7:0] cpu_spi_din;
  wire [7:0] dma_spi_din;
  wire [7:0] spi_dout;

  wire dma_wtp_req;
  wire dma_wtp_stb;
  wire wait_status_wrn;
  
  wire csrom;
  wire [15:0] rom_addr;
  wire [7:0] rom_do_bus;
  wire [7:0] roml_do_bus;
  wire [7:0] romh_do_bus;
  
  // Keyboard
wire [4:0] kb_do_bus;
wire [7:0] kb_joy_bus;
reg  [4:0] key;
wire       key_reset;
wire [7:0] key_scancode;
wire [7:0]  mouse_do;
wire n_reset;

wire [7:0] clocktm;
  // wire [1:0] vg_ddrv;
  // assign vg_a[0] = vg_ddrv[0] ? 1'b1 : 1'b0; // possibly open drain?
  // assign vg_a[1] = vg_ddrv[1] ? 1'b1 : 1'b0;

//  assign rom_addr = {rompg[1:0],cpu_a_bus[13:0]};
  assign rom_addr = {rompg[1:0],cpu_a_bus[13:0]};
  
//  assign nmi_n = 1'bZ;
//  assign res = ~rst_n;
//  assign rompg0_n = ~rompg[0];
//  assign dos_n    =  rompg[1];
//  assign rompg2   =  rompg[2];
//  assign rompg3   =  rompg[3];
//  assign rompg4   =  rompg[4];

//`ifdef IDE_HDD
  assign ide_rs_n = rst_n;
//`endif

// clock
wire clk_28mhz;// = clk & ce;

BUFGCE U_BUFG (
.O(clk_28mhz),
.I(clk),
.CE(ce)
);

assign clk_bus = clk_28mhz;

  t80pa t80pa
  (
    .RESET_n (rst_n),        //    : in  std_logic;
    .CLK   (clk_28mhz),
    .CEN_p (zpos),
    .CEN_n (zneg),
    .WAIT_n (1'b1),          //    : in  std_logic := '1';
    .INT_n (cpu_int_n_TS),   //    : in  std_logic := '1';
    .NMI_n (1'b1),           //    : in  std_logic := '1';
    .BUSRQ_n (1'b1),         //    : in  std_logic := '1';
    .M1_n (cpu_m1_n),        //    : out std_logic;
    .MREQ_n (cpu_mreq_n),    //    : out std_logic;
    .IORQ_n (cpu_iorq_n),    //    : out std_logic;
    .RD_n (cpu_rd_n),        //    : out std_logic;
    .WR_n (cpu_wr_n),        //    : out std_logic;
    .RFSH_n (cpu_rfsh_n),    //    : out std_logic;
//    .HALT_n      : out std_logic;
//    .BUSAK_n     : out std_logic;
    .OUT0 (1'b1),            //    : in  std_logic := '0';  -- 0 => OUT(C),0, 1 => OUT(C),255
    .A  (cpu_a_bus),         //    : out std_logic_vector(15 downto 0);
    .DI (cpu_di_bus),        //    : in  std_logic_vector(7 downto 0);
    .DO (cpu_do_bus),        //    : out std_logic_vector(7 downto 0);
//    .REG         : out std_logic_vector(211 downto 0); -- IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
    .DIRSet (1'b0) //      : in  std_logic := '0';
//    .DIR         : in  std_logic_vector(211 downto 0) := (others => '0') -- IFF2, IFF1, IM, IY, HL', DE', BC', IX, HL, DE, BC, PC, SP, R, I, F', A', F, A
    );
	 
  clock clock
  (
    .clk(clk_28mhz),
    .f0(f0),
    .f1(f1),
    .h0(h0),
    .h1(h1),
    .c0(c0),
    .c1(c1),
    .c2(c2),
    .c3(c3),
    .ay_clk(/*ay_clk*/),
	 .clocktm(clocktm),
    .ay_mod(2'b00)
  );

  resetter myrst
  (
    .clk(clk_28mhz),
    .rst_in_n(n_reset),
    .rst_out_n(rst_n)
  );

 wire zclkn;
 
  zclock zclock
  (
    .clk(clk_28mhz),
    .c0(c0),
    .c2(c2),
    .iorq_s(iorq_s),
    .zclk_out(zclkn),
    .zpos(zpos),
    .zneg(zneg),
    .turbo(turbo),
    .dos_on(dos_on),
    .vdos_off(vdos_off),
    .cpu_stall(cpu_stall),
    .ide_stall(ide_stall),
    .external_port(external_port)
  );

 assign zclk = !zclkn; 
/*  zbus zxbus
  (
    .iorq(iorq),
    .iorq_n(iorq_n),
    .rd(zrd),
    .iorq1_n(iorq1_n),
    .iorq2_n(iorq2_n),
    .iorqge1(iorqge1),
    .iorqge2(iorqge2),
    .porthit(porthit),
    .drive_ff(drive_ff)
  );*/

  zmem zmem
  (
    .clk(clk_28mhz),
    .c1(c1),
    .c2(c2),
    .c3(c3),
    .rst(rst),
    .zneg(zneg),
    .za(cpu_a_bus),
    .zd_out(dout_ram),
    .zd_ena(ena_ram),
    .opfetch(opfetch),
    .opfetch_s(opfetch_s),
    .memrd(memrd),
    .memwr(memwr),
    .memwr_s(memwr_s),
    .memconf(memconf[3:0]),
    .xt_page(xt_page),
    .rompg(rompg),
    .cache_en(cacheconf[3:0]),
    .romoe_n(/*romoe_n*/),
    .romwe_n(/*romwe_n*/),
    .csrom(csrom),
    .dos(dos),
    .dos_on(dos_on),
    .dos_off(dos_off),
    .vdos(vdos),
    .pre_vdos(pre_vdos),
    .vdos_on(vdos_on),
    .vdos_off(vdos_off),
    .cpu_req(cpu_req),
    .cpu_wrbsel(cpu_wrbsel),
    .cpu_strobe(cpu_strobe),
    .cpu_latch(cpu_latch),
    .cpu_addr(cpu_addr),
    .cpu_rddata(sram_do_bus_16),
    .cpu_stall(cpu_stall),
    .cpu_next(cpu_next),
    .turbo(turbo)
  );

  sram sram
  (
    .clk(clk),
	 .cyc(ce&c3),
    .addr(daddr),
    .wrdata(dram_wrdata),
    .bsel(dbsel),
    .req(dreq),
    .rnw(drnw),
    .c0(c0),
    .c1(c1),
    .c2(c2),
    .c3(c3),
    .sram_addr(sram_addr),
	 .sram_data(sram_data),
    .sram_we_n(sram_we_n),
	 .sram_rd_n(sram_rd_n),
	 .sram_do(sram_do_bus_16)
  );

  arbiter arbiter
  (
    .clk(clk_28mhz),
    .c1(c1),
    .c2(c2),
    .c3(c3),
    .dram_addr(daddr),
    .dram_req(dreq),
    .dram_rnw(drnw),
    .dram_bsel(dbsel),
    .dram_wrdata(dram_wrdata),
    .cpu_addr(cpu_addr),
    .cpu_wrdata    (cpu_do_bus),
    .cpu_req(cpu_req),
    .cpu_rnw(zrd),
    .cpu_wrbsel(cpu_wrbsel),
    .cpu_next(cpu_next),
    .cpu_strobe(cpu_strobe),
    .cpu_latch(cpu_latch),
    .curr_cpu_o(curr_cpu),
	 
    .video_go(video_go),
    .video_bw(video_bw),
    .video_addr(video_addr),
    .video_strobe(video_strobe),
    .video_pre_next(video_pre_next),
    .video_next(video_next),
    .next_vid(next_video),
    .dma_addr(dma_addr),
    .dma_wrdata(dma_wrdata),
    .dma_req(dma_req),
    .dma_rnw(dma_rnw),
    .dma_next(dma_next),
    .ts_req(ts_req),
    .ts_addr(ts_addr),
    .ts_pre_next(ts_pre_next),
    .ts_next(ts_next),
    .tm_addr(tm_addr),
    .tm_req(tm_req),
    .tm_next(tm_next)
  );

  video_top video_top
  (
    .clk(clk_28mhz),
    .res(rst),
    .f0(f0),
    .f1(f1),
    .h1(h1),
    .c0(c0),
    .c1(c1),
    .c3(c3),
    .vred(/*vred*/),
    .vgrn(/*vgrn*/),
    .vblu(/*vblu*/),
    .vred_raw(vred_raw),
    .vgrn_raw(vgrn_raw),
    .vblu_raw(vblu_raw),
    .vdac_mode(vdac_mode),
	 .vdac2_msel(vdac2_sel),
    .hsync(hsync),
    .vsync(vsync),
    .csync(/*vcsync*/),
    .cfg_60hz(1'b0/*cfg_60hz*/),
    .vga_on(1'b1/*1'b1cfg_vga_on*/),
    .border_wr(border_wr),
    .zborder_wr(zborder_wr),
    .zvpage_wr(zvpage_wr),
    .vpage_wr(vpage_wr),
    .vconf_wr(vconf_wr),
    .gx_offsl_wr(gx_offsl_wr),
    .gx_offsh_wr(gx_offsh_wr),
    .gy_offsl_wr(gy_offsl_wr),
    .gy_offsh_wr(gy_offsh_wr),
    .t0x_offsl_wr(t0x_offsl_wr),
    .t0x_offsh_wr(t0x_offsh_wr),
    .t0y_offsl_wr(t0y_offsl_wr),
    .t0y_offsh_wr(t0y_offsh_wr),
    .t1x_offsl_wr(t1x_offsl_wr),
    .t1x_offsh_wr(t1x_offsh_wr),
    .t1y_offsl_wr(t1y_offsl_wr),
    .t1y_offsh_wr(t1y_offsh_wr),
    .palsel_wr(palsel_wr),
    .hint_beg_wr(hint_beg_wr),
    .vint_begl_wr(vint_begl_wr),
    .vint_begh_wr(vint_begh_wr),
    .tsconf_wr(tsconf_wr),
    .tmpage_wr(tmpage_wr),
    .t0gpage_wr(t0gpage_wr),
    .t1gpage_wr(t1gpage_wr),
    .sgpage_wr(sgpage_wr),
    .video_addr(video_addr),
    .video_bw(video_bw),
    .video_go(video_go),
    .dram_rdata(sram_do_bus_16), 
    .video_strobe(video_strobe),
    .video_pre_next(video_pre_next),
    .ts_req(ts_req),
    .ts_pre_next(ts_pre_next),
    .ts_addr(ts_addr),
    .ts_next(ts_next),
    .tm_addr(tm_addr),
    .tm_req(tm_req),
    .tm_next(tm_next),
    .d(cpu_do_bus),
    .zmd(zmd),
    .zma(zma),
    .cram_we(cram_we),
    .sfile_we(sfile_we),
    .int_start(int_start_frm),
    .line_start_s(int_start_lin)
  );

/*  slavespi slavespi
  (
    .fclk(fclk),
    .rst_n(rst_n),
    .spics_n(spics_n),
    .spidi(spidi),
    .spido(spido),
    .spick(spick),
    .status_in({wait_status_wrn, 5'b0, wait_status[1:0]}),
`ifndef SIMULATE
    .genrst(genrst),
`endif
    .kbd_out(kbd_data),
    .kbd_out_sel(kbd_data_sel),
    .kbd_stb(kbd_stb),
    .mus_out(mus_data),
    .mus_xstb(mus_xstb),
    .mus_ystb(mus_ystb),
    .mus_btnstb(mus_btnstb),
    .kj_stb(kj_stb),
    .wait_addr(wait_addr),
    .wait_write(wait_write),
    .wait_read(wait_read),
    .wait_end(wait_end),
    .config0(config0)
  );*/

  /*zkbdmus zkbdmus
  (
    .fclk(fclk),
    .rst_n(rst_n),
    .kbd_in(kbd_data),
    .kbd_in_sel(kbd_data_sel),
    .kbd_stb(kbd_stb),
    .mus_in(mus_data),
    .mus_xstb(mus_xstb),
    .mus_ystb(mus_ystb),
    .mus_btnstb(mus_btnstb),
    .kj_stb(kj_stb),
    .kj_data(kj_port_data),
    .zah(cpu_a_bus[15:8]),
    .kbd_data(kbd_port_data),
    .mus_data(mus_port_data)
  );*/

  zmaps zmaps
  (
    .clk(clk_28mhz),
    .memwr_s(memwr_s),
    .a(cpu_a_bus),
    .d(cpu_do_bus),
    .fmaddr(fmaddr),
    .zmd(zmd),
    .zma(zma),
    .dma_wraddr(dma_wraddr),
    .dma_data(dma_data),
    .dma_cram_we(dma_cram_we),
    .dma_sfile_we(dma_sfile_we),
    .cram_we(cram_we),
    .sfile_we(sfile_we),
    .regs_we(regs_we)
  );

  zsignals zsignals
  (
    .clk(clk_28mhz),
    .zpos(zpos),
    .rst_n(rst_n),
    .iorq_n(cpu_iorq_n),
    .mreq_n(cpu_mreq_n),
    .m1_n(cpu_m1_n),
    .rfsh_n(cpu_rfsh_n),
    .rd_n(cpu_rd_n),
    .wr_n(cpu_wr_n),
    .rst(rst),
    .m1(m1),
    .rfsh(rfsh),
    .rd(zrd),
    .wr(zwr),
    .iorq(iorq),
    .iorq_s(iorq_s),
    // .iorq_s2    (iorq_s2),
    .mreq(mreq),
    .mreq_s(mreq_s),
    .rdwr(rdwr),
    .iord(iord),
    .iowr(iowr),
    .iordwr(iordwr),
    .iord_s(iord_s),
    .iowr_s(iowr_s),
    .iordwr_s(iordwr_s),
    .memrd(memrd),
    .memwr(memwr),
    .memrw(memrw),
    .memrd_s(memrd_s),
    .memwr_s(memwr_s),
    .memrw_s(memrw_s),
    .opfetch(opfetch),
    .opfetch_s(opfetch_s),
    .intack(intack)
  );

  zports zports
  (
    .zclk(zclk),
    .clk(clk_28mhz),
    .din(cpu_do_bus),
    .dout(dout_ports),
    .dataout(ena_ports),
    .a(cpu_a_bus),
    .rst(rst),
    .opfetch(opfetch),
    .rd(zrd),
    .wr(zwr),
    .rdwr(rdwr),
    .iorq(iorq),
    .iord(iord),
    .iowr(iowr),
    .iordwr(iordwr),
    .iorq_s(iorq_s),
    .iord_s(iord_s),
    .iowr_s(iowr_s),
    .iordwr_s(iordwr_s),
    .ay_bdir(/*ay_bdir*/),
    .ay_bc1(/*ay_bc1*/),
    .vg_intrq(intrq),
    .vg_drq(drq),
    .vg_cs_n(vg_cs_n),
    .vg_wrFF(vg_wrFF),
    .sd_start(cpu_spi_req),
    .sd_dataout(spi_dout),
    .sd_datain(cpu_spi_din),
    .sdcs_n(sdcs_n),
`ifdef SD_CARD2
    .sd2cs_n(sd2cs_n),
`endif
//`ifdef IDE_VDAC2
    .ftcs_n(ftcs_n),
//`endif
//`ifdef IDE_HDD
    .ide_in(ide_d),
    .ide_out(z80_ide_out),
    .ide_cs0_n(z80_ide_cs0_n),
    .ide_cs1_n(z80_ide_cs1_n),
    .ide_req(z80_ide_req),
    .ide_stb(ide_stb),
    .ide_ready(ide_ready),
    .ide_stall(ide_stall),
//`endif
    .border_wr(border_wr),
    .zborder_wr(zborder_wr),
    .zvpage_wr(zvpage_wr),
    .vpage_wr(vpage_wr),
    .vconf_wr(vconf_wr),
    .gx_offsl_wr(gx_offsl_wr),
    .gx_offsh_wr(gx_offsh_wr),
    .gy_offsl_wr(gy_offsl_wr),
    .gy_offsh_wr(gy_offsh_wr),
    .t0x_offsl_wr(t0x_offsl_wr),
    .t0x_offsh_wr(t0x_offsh_wr),
    .t0y_offsl_wr(t0y_offsl_wr),
    .t0y_offsh_wr(t0y_offsh_wr),
    .t1x_offsl_wr(t1x_offsl_wr),
    .t1x_offsh_wr(t1x_offsh_wr),
    .t1y_offsl_wr(t1y_offsl_wr),
    .t1y_offsh_wr(t1y_offsh_wr),
    .palsel_wr(palsel_wr),
    .hint_beg_wr(hint_beg_wr),
    .vint_begl_wr(vint_begl_wr),
    .vint_begh_wr(vint_begh_wr),
    .tsconf_wr(tsconf_wr),
    .tmpage_wr(tmpage_wr),
    .t0gpage_wr(t0gpage_wr),
    .t1gpage_wr(t1gpage_wr),
    .sgpage_wr(sgpage_wr),
    .xt_page(xt_page),
    .fmaddr(fmaddr),
    .regs_we(regs_we),
    .sysconf(sysconf),
    .cacheconf(cacheconf),
    .memconf(memconf),
    .intmask(intmask),
    .fddvirt(fddvirt),
/*`ifdef FDR
    .fdr_cnt(fdr_cnt),
    .fdr_en(fdr_en),
    .fdr_cnt_lat(fdr_cnt_lat),
`endif*/
    .cfg_floppy_swap(cfg_floppy_swap),
    .drive_sel(vg_a),
    .dos(dos),
    .vdos(vdos),
    .vdos_on(vdos_on),
    .vdos_off(vdos_off),
    .dmaport_wr(dmaport_wr),
    .dma_act(dma_act),
    .dmawpdev(dmawpdev),
    .keys_in(kb_do_bus),
    .mus_in(mouse_do),
    .kj_in(joy_data[7:0]),
    .tape_read(tape_in),
    .beeper_wr(beeper_wr),
    .covox_wr(covox_wr),
    .wait_addr(wait_addr),
    .wait_start_gluclock(wait_start_gluclock),
    .wait_start_comport(wait_start_comport),
    .wait_read(mc146818a_do_bus),
    .wait_write(wait_write),
    .porthit(porthit),
	 .clocktm(clocktm),
    .external_port(external_port)
  );

  dma dma
  (
    .clk(clk_28mhz),
    .c2(c2),
    .rst_n(rst_n),
    .int_start(int_start_dma),
    .zdata(cpu_do_bus),
    .dmaport_wr(dmaport_wr),
    .dma_act(dma_act),
    .dram_addr(dma_addr),
    .dram_rnw(dma_rnw),
    .dram_req(dma_req),
    .dram_rddata(sram_do_bus_16),
    .dram_wrdata(dma_wrdata),
    .dram_next(dma_next),
    .data(dma_data),
    .wraddr(dma_wraddr),
    .cram_we(dma_cram_we),
    .sfile_we(dma_sfile_we),
//`ifdef IDE_HDD
    .ide_in(ide_d),
    .ide_out(dma_ide_out),
    .ide_req(dma_ide_req),
    .ide_rnw(dma_ide_rnw),
    .ide_stb(ide_stb),
//`endif
    .spi_req(dma_spi_req),
    .spi_stb(spi_start),
    .spi_rddata(spi_dout),
    .spi_wrdata(dma_spi_din),
    .wtp_req(dma_wtp_req),
    .wtp_stb(dma_wtp_stb),
    .wtp_rddata(mus_data)   // data must be available 1 clk earlier than wait_data (mus_data = shift_in in slavespi.v)
    // .wtp_wrdata(dma_wtp_din)
/*`ifdef FDR
    ,
    .fdr_in(fdr_rle),
    .fdr_req(fdr_req),
    .fdr_stb(fdr_stb),
    .fdr_stop(fdr_stop)
`endif*/
  );

/*  wire [7:0] fdr_rle;
  wire [18:0] fdr_cnt;
  wire fdr_req;
  wire fdr_stb;
  wire fdr_stop;
  wire fdr_en;
  wire fdr_cnt_lat;

  fddrip fddrip
  (
    .clk(fclk),
    .rdat_n(rdat_b_n),
    .reset(!fdr_en),
    .cnt_latch(fdr_cnt_lat),
    .data(fdr_rle),
    .data_cnt_l(fdr_cnt),
    .req(fdr_req),
    .stb(fdr_stb),
    .stop(fdr_stop)
  );*/

  zint zint
  (
    .clk(clk_28mhz),
    .zpos(zpos),
    .res(rst),
    .wait_n(1'b1/*wait_n*/),
    .im2vect(im2vect),
    .intmask(intmask),
//`ifdef IDE_VDAC2
	 .int_start_lin(vdac2_sel ? int_start_ft : int_start_lin),
//`else
//    .int_start_lin(int_start_lin),
//`endif
    .int_start_frm(int_start_frm),
    .int_start_dma(int_start_dma),
    .int_start_wtp(1'b0/*int_start_wtp*/),
    .vdos(pre_vdos),
    .intack(intack),
    .int_n(cpu_int_n_TS)
  );

//  znmi znmi
//  (
    // .rst_n(rst_n),
    // .fclk(fclk),
    // .zpos(zpos),
    // .zneg(zneg),
    // .rfsh_n(rfsh_n),
    // .int_start(int_start),
    // .set_nmi(set_nmi),
    // .clr_nmi(clr_nmi)
    // .in_nmi(in_nmi),    // commented to disable
    // .gen_nmi(gen_nmi)
//  );

/*
  zwait zwait
  (
    .fclk(fclk),
    .wait_start_gluclock(wait_start_gluclock),
    .wait_start_comport(wait_start_comport),
    .dma_wtp_req(dma_wtp_req),
    .dma_wtp_stb(dma_wtp_stb),
    .dmawpdev(dmawpdev),
    .wr_n(cpu_wr_n),
    .wait_end(wait_end),
    .rst_n(rst_n),
    .wait_n(wait_n),
    .wait_status(wait_status),
    .wait_status_wrn(wait_status_wrn),
    .spiint_n(spiint_n)
  );*/

//  vg93 vgshka
//  (
//    .zclk(zclk),
//    .rst_n(rst_n),
//    .fclk(fclk),
//    .vg_clk(vg_clk),
//    .vg_res_n(vg_res_n),
//    .din(d),
//    .intrq(intrq),
//    .drq(drq),
//    .vg_wrFF(vg_wrFF),
//    .vg_hrdy(vg_hrdy),
//    .vg_rclk(vg_rclk),
//    .vg_rawr(vg_rawr),
//    .vg_wrd(vg_wrd),
//    .vg_side(vg_side),
//    .step(step),
//    .vg_sl(vg_sl),
//    .vg_sr(vg_sr),
//    .vg_tr43(vg_tr43),
//    .rdat_n(rdat_b_n),
//    .vg_drq(vg_drq),
//    .vg_irq(vg_irq),
//    .vg_wd(vg_wd)
//  );

  spi spi
  (
    .clk(clk_28mhz),
    .sck(sdclk),
    .sdo(sddo),
//`ifdef IDE_VDAC2
    .sdi(!ftcs_n ? ftdi : sddi),
//`else
//    .sdi(sddi),
//`endif
    .dma_req(dma_spi_req),
    .dma_din(dma_spi_din),
    .cpu_req(cpu_spi_req),
    .cpu_din(cpu_spi_din),
    .start(spi_start),
    .dout(spi_dout)
  );
  
 assign ftclk = sdclk;
 assign ftdo = sddo;
 // todo: ftint, vdac2_sel
 reg [1:0] ftint_r;
// wire ftcs_n;
 wire ft_int = ftint;
 wire int_start_ft = ftint_r[1] && !ftint_r[0];
 
 always @(posedge clk_28mhz)
	ftint_r <= {ftint_r[0], ft_int};
 

//`ifdef IDE_HDD
  ide ide
  (
    .clk(clk_28mhz),
    .reset(rst),
    .rdy_stb(ide_stb),
    .rdy(ide_ready),
    .ide_out(ide_out),
    .ide_a(ide_a),
    .ide_dir(ide_dir),
    .ide_cs0_n(ide_cs0_n),
    .ide_cs1_n(ide_cs1_n),
    .ide_rd_n(ide_rd_n),
    .ide_wr_n(ide_wr_n),
    .dma_out(dma_ide_out),
    .dma_req(dma_ide_req),
    .dma_rnw(dma_ide_rnw),
    .z80_out(z80_ide_out),
    .z80_a(cpu_a_bus[7:5]),
    .z80_cs0_n(z80_ide_cs0_n),
    .z80_cs1_n(z80_ide_cs1_n),
    .z80_req(z80_ide_req),
    .z80_rnw(!cpu_rd_n)            // this should be the direct Z80 signal
  );
  assign ide_d = ide_dir ? 16'hZZZZ : ide_out;
//`endif

  wire [7:0] covox_beeper_out;
  sound sound
  (
    .clk(clk_28mhz),
    .din(cpu_do_bus),
    .beeper_wr(beeper_wr),
    .covox_wr(covox_wr),
    .sound(covox_beeper_out)
  );

  vdac vdac
  (
    .clk(clk_28mhz),
    .vred_raw(vred_raw),
    .vgrn_raw(vgrn_raw),
    .vblu_raw(vblu_raw),
    .vdac_mode(vdac_mode),
    .hsync(hsync),
    .vsync(vsync),
    .red_o(VGA_R),
    .grn_o(VGA_G),
    .blu_o(VGA_B),
    .hsync_o(VGA_HS),
    .vsync_o(VGA_VS)
  );

  rom rom
  (
    .clk (clk_28mhz),
    .a(rom_addr),
    .dout(rom_do_bus)
  );
  
// keyboard
assign keyboard_addr = cpu_a_bus[15:8];
assign kb_do_bus = keyboard_data;
assign key_scancode = keyboard_scancode;

// mouse   
assign mouse_addr = cpu_a_bus[10:8];
assign mouse_do = mouse_data;
  
// rtc
assign rtc_addr = wait_addr;
assign rtc_di = cpu_do_bus;
assign mc146818a_do_bus = rtc_do;
assign rtc_wr = wait_start_gluclock & ~cpu_wr_n;

// turbosound

wire ts_enable = ~cpu_iorq_n & cpu_a_bus[0] & cpu_a_bus[15] & ~cpu_a_bus[1];
wire ts_we     = ts_enable & ~cpu_wr_n;
wire  [7:0] ts_do, ts_do0, ts_do1;
wire ts_sel;
wire [7:0] ts_ssg0_a, ts_ssg0_b, ts_ssg0_c, ts_ssg1_a, ts_ssg1_b, ts_ssg1_c;

reg ce_ym;
reg [5:0] div;
always @(posedge clk_28mhz) begin
	div <= div + 1'd1;
	ce_ym <= !div[3] & !div[2] & !div[1] & !div[0]; // 1.75
end

turbosound turbosound
(
	.I_CLK(clk_28mhz),
	.I_ENA(ce_ym),
	.I_ADDR(cpu_a_bus),
	.I_DATA(cpu_do_bus),
	.I_WR_N(cpu_wr_n),
	.I_IORQ_N(cpu_iorq_n),
	.I_M1_N(cpu_m1_n),
	.I_RESET_N(~rst),

	.I_BDIR(ts_we),
	.I_BC1(cpu_a_bus[14]),
	.O_SEL(ts_sel),
	.I_MODE(~psg_type), // todo: mode AY/YM from mcu
	
	.O_SSG0_DA(ts_do0),
	.O_SSG1_DA(ts_do1),
	
	.O_SSG0_AUDIO_A(ts_ssg0_a),
	.O_SSG0_AUDIO_B(ts_ssg0_b),
	.O_SSG0_AUDIO_C(ts_ssg0_c),

	.O_SSG1_AUDIO_A(ts_ssg1_a),
	.O_SSG1_AUDIO_B(ts_ssg1_b),
	.O_SSG1_AUDIO_C(ts_ssg1_c)	
);

assign ts_do = ts_sel ? ts_do1 : ts_do0;

// SAA1099

wire saa_wr_n;
wire [7:0] saa_out_l;
wire [7:0] saa_out_r;

saa1099 saa1099
(
	.clk(clk8),
	.rst_n(~rst),
	.cs_n(1'b0),
	.a0(cpu_a_bus[8]),
	.wr_n(saa_wr_n),
	.din(cpu_do_bus),
	.out_l(saa_out_l),
	.out_r(saa_out_r)
);

assign saa_wr_n = cpu_iorq_n || cpu_wr_n || ~(cpu_a_bus[7:0] == 8'hFF);

// beeper / tape out

reg [7:0] port_xxfe_reg;
always @(posedge clk_28mhz) begin
	if (rst) port_xxfe_reg <= 0;
	else if (~cpu_iorq_n && ~cpu_wr_n && cpu_a_bus[7:0] == 8'hFE) port_xxfe_reg <= cpu_do_bus;
end

assign tape_out = port_xxfe_reg[3];

// covox

wire [7:0] covox_a, covox_b, covox_c, covox_d, covox_fb;

covox covox
(
	.I_RESET(rst),
	.I_CLK(clk_28mhz),
	.I_CS(covox_en),
	.I_ADDR(cpu_a_bus[7:0]),
	.I_DATA(cpu_do_bus),
	.I_WR_N(cpu_wr_n),
	.I_IORQ_N(cpu_iorq_n),
	
	.I_DOS(dos), 
	
	.O_A(covox_a),
	.O_B(covox_b),
	.O_C(covox_c),
	.O_D(covox_d),
	.O_FB(covox_fb)
);

// audio mixer

audio_mixer audio_mixer
(
	.clk(clk_28mhz),

	.mute(1'b0), // todo: switchable from osd / on pause 
	.mode(psg_mix), 
	
	.speaker(port_xxfe_reg[4]),
	.tape_in(tape_in), 
	
	.ssg0_a(ts_ssg0_a),
	.ssg0_b(ts_ssg0_b),
	.ssg0_c(ts_ssg0_c),
	.ssg1_a(ts_ssg1_a),
	.ssg1_b(ts_ssg1_b),
	.ssg1_c(ts_ssg1_c),
	
	.covox_a(covox_a),
	.covox_b(covox_b),
	.covox_c(covox_c),
	.covox_d(covox_d),
	.covox_fb(covox_fb),
	
	.saa_l(saa_out_l),
	.saa_r(saa_out_r),
	
	.audio_l(audio_out_l),
	.audio_r(audio_out_r)
	
);

assign n_reset = locked & resetbtn_n;

assign cpu_di_bus = 
		(csrom && ~cpu_mreq_n && ~cpu_rd_n) 						?	rom_do_bus			:	// BIOS
		ena_ram    															?	dout_ram 			:	// SDRAM
		(ts_enable && ~cpu_rd_n)										?	ts_do					:	// TurboSound
		(~zifi_oe_n)														?  zifi_do_bus       :  // zifi
		(fdc_oe)																?  fdc_do_bus 			:  // floppy
		(ena_ports)															?	dout_ports			:  // zports
		(intack)																?	im2vect 				:
																					8'b11111111; 

// zifi
wire [7:0] zifi_do_bus;
wire zifi_oe_n;

zifi zifi(
	.CLK(clk_28mhz),
	.RESET(rst),
	.DS80(1'b0),
	
	.A(cpu_a_bus),
	.DI(cpu_do_bus),
	.DO(zifi_do_bus),
	.IORQ_N(cpu_iorq_n),
	.RD_N(cpu_rd_n),
	.WR_N(cpu_wr_n),
	
	.ZIFI_OE_N(zifi_oe_n),
	.ENABLED(),
	.UART_RX(uart_rx),
	.UART_TX(uart_tx),
	.UART_CTS(uart_cts)
);

// fdc

wire fdc_oe;
wire [7:0] fdc_do_bus;
wire [1:0] vg_a;
wire vg_cs_n;
//assign fdc_ds = vg_a;

always @(vg_a)
begin
	case ({fdc_motor, vg_a}) 
		3'b100: fdc_ds <= 2'b01;
		3'b101: fdc_ds <= 2'b10;
		default: fdc_ds <= 2'b00;
	endcase
end


Firefly_FDC fdc
(
	.iCLK(clk_28mhz),
	.iCLK16(clk_16), 
	.iRESET(rst),

	.iADDR(cpu_a_bus),
	.iDATA(cpu_do_bus),
	.iM1(cpu_m1_n),
	.iWR(cpu_wr_n),
	.iRD(cpu_rd_n),
	.iIORQ(cpu_iorq_n),
	
	.iDOS(dos),
	.iVDOS(vdos),
   .iCSn(vg_cs_n),
   .iWRFF(vg_wrFF),

	.oCS(fdc_oe),		
	.oDATA(fdc_do_bus), 

	.oFDC_SIDE1(fdc_side),
	.iFDC_RDATA(fdc_rdata),
	.iFDC_WPRT(fdc_wprt),
	.iFDC_TR00(fdc_tr00),
	.iFDC_INDEX(fdc_index),
	.oFDC_WG(fdc_wg),
	.oFDC_WR_DATA(fdc_wr_data),
	.oFDC_STEP(fdc_step),
	.oFDC_DIR(fdc_dir),
	.oFDC_MOTOR(fdc_motor),
	.oFDC_DS()
);	

endmodule
