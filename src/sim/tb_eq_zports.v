`timescale 1ns / 1ps

// zports (rtl/tsconf/zports.v) against the version of cec5631 (sim/ref/zports_ref.v): its registers clocked by
// zclk (= !zclk_out of zclock.v, which rises at the negedge clk with zpos) are now on negedge clk with zpos as the
// enable, its IDE trigger latches (transparent outside the cycle) registers with a bypass. zclock.v makes zclk and
// zpos, with the turbo mode and the stalls changing at random. The bus changes at the rising clk as the T80 drives
// it: I/O and memory cycles of 2 to 12 clocks, the port addresses of zports and random ones, random data and
// inputs, a reset now and then. Every output is compared after both edges of clk.
// Ends with "tb_eq_zports: N errors".

module tb_eq_zports;

parameter CLOCKS = 4000000;

reg clk = 1'b0;
always #17.84 clk = ~clk; // clk_bus

integer seed = 11;

// z80 clock: zclock.v with the c0 / c2 phases of a 4-clock cycle (clock.v), turbo and stalls at random
reg [1:0] cnt = 2'd0;
always @(posedge clk) cnt <= cnt + 2'd1;
wire c0 = (cnt == 2'd0), c2 = (cnt == 2'd2);
reg [1:0] turbo = 2'b00;
reg cpu_stall = 1'b0, ide_stall_in = 1'b0;
wire zclk_out, zpos, zneg;
zclock zclock(.clk(clk), .zclk_out(zclk_out), .c0(c0), .c2(c2), .iorq_s(1'b0), .external_port(1'b0),
	.zpos(zpos), .zneg(zneg), .cpu_stall(cpu_stall), .ide_stall(ide_stall_in), .dos_on(1'b0), .vdos_off(1'b0),
	.turbo(turbo));
wire zclk = !zclk_out;

// inputs (zpos, clk above)
reg [7:0] din = 8'd0;
reg [15:0] a = 16'd0;
reg rst = 1'd0;
reg opfetch = 1'd0;
reg rd = 1'd0;
reg wr = 1'd0;
reg rdwr = 1'd0;
reg iorq = 1'd0;
reg iorq_s = 1'd0;
reg iord = 1'd0;
reg iord_s = 1'd0;
reg iowr = 1'd0;
reg iowr_s = 1'd0;
reg iordwr = 1'd0;
reg iordwr_s = 1'd0;
reg regs_we = 1'd0;
reg cfg_floppy_swap = 1'd0;
reg dma_act = 1'd0;
reg dos = 1'd0;
reg vdos = 1'd0;
reg tape_read = 1'd0;
reg [15:0] ide_in = 16'd0;
reg ide_stb = 1'd0;
reg ide_ready = 1'd0;
reg [4:0] keys_in = 5'd0;
reg [7:0] mus_in = 8'd0;
reg [7:0] kj_in = 8'd0;
reg vg_intrq = 1'd0;
reg vg_drq = 1'd0;
reg espcs_in = 1'd0;
reg [7:0] sd_dataout = 8'd0;
reg [7:0] wait_read = 8'd0;

// the bus: a cycle at a time, changing at the rising clk
localparam NPORT = 40;
reg [7:0] port_lo [0:NPORT-1];
initial begin
	port_lo[0] = 8'hFE; port_lo[1] = 8'hFD; port_lo[2] = 8'hAF; port_lo[3] = 8'hF7; port_lo[4] = 8'hFB;
	port_lo[5] = 8'h10; port_lo[6] = 8'h11; port_lo[7] = 8'h30; port_lo[8] = 8'h50; port_lo[9] = 8'h70;
	port_lo[10] = 8'h90; port_lo[11] = 8'hB0; port_lo[12] = 8'hD0; port_lo[13] = 8'hF0; port_lo[14] = 8'h08;
	port_lo[15] = 8'hC8; port_lo[16] = 8'h1F; port_lo[17] = 8'h3F; port_lo[18] = 8'h5F; port_lo[19] = 8'h7F;
	port_lo[20] = 8'hFF; port_lo[21] = 8'hDF; port_lo[22] = 8'h77; port_lo[23] = 8'h57; port_lo[24] = 8'hEF;
	port_lo[25] = 8'h10; port_lo[26] = 8'h11; port_lo[27] = 8'h10; port_lo[28] = 8'h11; port_lo[29] = 8'hC8;
	port_lo[30] = 8'hAF; port_lo[31] = 8'hAF; port_lo[32] = 8'hEF; port_lo[33] = 8'hF7; port_lo[34] = 8'h28;
	port_lo[35] = 8'h48; port_lo[36] = 8'h68; port_lo[37] = 8'h88; port_lo[38] = 8'hA8; port_lo[39] = 8'hE8;
end

integer left = 0;
reg [2:0] kind = 3'd0; // 0 idle, 1 I/O read, 2 I/O write, 3 memory read, 4 memory write, 5 opcode fetch
reg [31:0] r;
always @(posedge clk) begin
	r = $random(seed);
	if (left == 0) begin
		left <= 2 + (r[3:0] % 11);
		kind <= (r[6:4] < 3'd6) ? r[6:4] : 3'd1;
		a <= {$random(seed)} % 65536;
		if (r[7]) a[7:0] <= port_lo[{$random(seed)} % NPORT];
		din <= $random(seed);
	end
	else
		left <= left - 1;
	rd <= (kind == 3'd1 || kind == 3'd3 || kind == 3'd5) && left != 0;
	wr <= (kind == 3'd2 || kind == 3'd4) && left != 0;
	rdwr <= (kind != 3'd0) && left != 0;
	iorq <= (kind == 3'd1 || kind == 3'd2) && left != 0;
	iorq_s <= iorq;
	iord <= (kind == 3'd1) && left != 0;
	iord_s <= iord;
	iowr <= (kind == 3'd2) && left != 0;
	iowr_s <= iowr;
	iordwr <= (kind == 3'd1 || kind == 3'd2) && left != 0;
	iordwr_s <= iordwr;
	opfetch <= (kind == 3'd5) && left != 0;
	// the other inputs
	if (r[15:8] == 0) begin
		dos <= $random(seed); vdos <= $random(seed); cfg_floppy_swap <= $random(seed); dma_act <= $random(seed);
		espcs_in <= $random(seed);
	end
	regs_we <= (r[23:16] == 0);
	if (regs_we) a <= $random(seed);
	tape_read <= r[24]; vg_intrq <= r[25]; vg_drq <= r[26];
	ide_stb <= (r[29:27] == 0); ide_ready <= r[30];
	if (r[31]) begin
		ide_in <= $random(seed); keys_in <= $random(seed); mus_in <= $random(seed); kj_in <= $random(seed);
		sd_dataout <= $random(seed); wait_read <= $random(seed);
	end
	if (($random(seed) & 16383) == 0) begin turbo <= $random(seed); cpu_stall <= 1'b0; end
	if (($random(seed) & 255) == 0) cpu_stall <= ~cpu_stall;
	if (($random(seed) & 255) == 0) ide_stall_in <= ~ide_stall_in;
	rst <= (($random(seed) & 65535) == 0) || ($time < 500);
end

wire [7:0] o_dout;
wire o_dataout;
wire o_porthit;
wire o_external_port;
wire [7:0] o_xt_wr_data;
wire [7:0] o_xt_wr_addr;
wire o_zborder_wr;
wire o_border_wr;
wire o_zvpage_wr;
wire o_vpage_wr;
wire o_vconf_wr;
wire o_gx_offsl_wr;
wire o_gx_offsh_wr;
wire o_gy_offsl_wr;
wire o_gy_offsh_wr;
wire o_t0x_offsl_wr;
wire o_t0x_offsh_wr;
wire o_t0y_offsl_wr;
wire o_t0y_offsh_wr;
wire o_t1x_offsl_wr;
wire o_t1x_offsh_wr;
wire o_t1y_offsl_wr;
wire o_t1y_offsh_wr;
wire o_tsconf_wr;
wire o_palsel_wr;
wire o_tmpage_wr;
wire o_t0gpage_wr;
wire o_t1gpage_wr;
wire o_sgpage_wr;
wire o_hint_beg_wr;
wire o_vint_begl_wr;
wire o_vint_begh_wr;
wire [31:0] o_xt_page;
wire [4:0] o_fmaddr;
wire [7:0] o_sysconf;
wire [7:0] o_memconf;
wire [3:0] o_cacheconf;
wire [7:0] o_fddvirt;
wire [8:0] o_dmaport_wr;
wire [1:0] o_dmawpdev;
wire [7:0] o_intmask;
wire o_vdos_on;
wire o_vdos_off;
wire o_ay_bdir;
wire o_ay_bc1;
wire o_covox_wr;
wire o_beeper_wr;
wire [15:0] o_ide_out;
wire o_ide_cs0_n;
wire o_ide_cs1_n;
wire o_ide_req;
wire o_ide_stall;
wire o_vg_cs_n;
wire o_vg_wrFF;
wire [1:0] o_drive_sel;
wire o_sdcs_n;
wire o_sd2cs_n;
wire o_ftcs_n;
wire o_espcs_n;
wire o_esp_ft_spi_dis;
wire o_spi_mode;
wire o_sd_start;
wire [7:0] o_sd_datain;
wire [7:0] o_wait_addr;
wire o_wait_start_gluclock;
wire o_wait_start_comport;
wire [7:0] o_wait_write;
zports_ref o_dut(
	.zclk(zclk),
	.clk(clk),
	.din(din),
	.a(a),
	.rst(rst),
	.opfetch(opfetch),
	.rd(rd),
	.wr(wr),
	.rdwr(rdwr),
	.iorq(iorq),
	.iorq_s(iorq_s),
	.iord(iord),
	.iord_s(iord_s),
	.iowr(iowr),
	.iowr_s(iowr_s),
	.iordwr(iordwr),
	.iordwr_s(iordwr_s),
	.regs_we(regs_we),
	.cfg_floppy_swap(cfg_floppy_swap),
	.dma_act(dma_act),
	.dos(dos),
	.vdos(vdos),
	.tape_read(tape_read),
	.ide_in(ide_in),
	.ide_stb(ide_stb),
	.ide_ready(ide_ready),
	.keys_in(keys_in),
	.mus_in(mus_in),
	.kj_in(kj_in),
	.vg_intrq(vg_intrq),
	.vg_drq(vg_drq),
	.espcs_in(espcs_in),
	.sd_dataout(sd_dataout),
	.wait_read(wait_read),
	.dout(o_dout),
	.dataout(o_dataout),
	.porthit(o_porthit),
	.external_port(o_external_port),
	.xt_wr_data(o_xt_wr_data),
	.xt_wr_addr(o_xt_wr_addr),
	.zborder_wr(o_zborder_wr),
	.border_wr(o_border_wr),
	.zvpage_wr(o_zvpage_wr),
	.vpage_wr(o_vpage_wr),
	.vconf_wr(o_vconf_wr),
	.gx_offsl_wr(o_gx_offsl_wr),
	.gx_offsh_wr(o_gx_offsh_wr),
	.gy_offsl_wr(o_gy_offsl_wr),
	.gy_offsh_wr(o_gy_offsh_wr),
	.t0x_offsl_wr(o_t0x_offsl_wr),
	.t0x_offsh_wr(o_t0x_offsh_wr),
	.t0y_offsl_wr(o_t0y_offsl_wr),
	.t0y_offsh_wr(o_t0y_offsh_wr),
	.t1x_offsl_wr(o_t1x_offsl_wr),
	.t1x_offsh_wr(o_t1x_offsh_wr),
	.t1y_offsl_wr(o_t1y_offsl_wr),
	.t1y_offsh_wr(o_t1y_offsh_wr),
	.tsconf_wr(o_tsconf_wr),
	.palsel_wr(o_palsel_wr),
	.tmpage_wr(o_tmpage_wr),
	.t0gpage_wr(o_t0gpage_wr),
	.t1gpage_wr(o_t1gpage_wr),
	.sgpage_wr(o_sgpage_wr),
	.hint_beg_wr(o_hint_beg_wr),
	.vint_begl_wr(o_vint_begl_wr),
	.vint_begh_wr(o_vint_begh_wr),
	.xt_page(o_xt_page),
	.fmaddr(o_fmaddr),
	.sysconf(o_sysconf),
	.memconf(o_memconf),
	.cacheconf(o_cacheconf),
	.fddvirt(o_fddvirt),
	.dmaport_wr(o_dmaport_wr),
	.dmawpdev(o_dmawpdev),
	.intmask(o_intmask),
	.vdos_on(o_vdos_on),
	.vdos_off(o_vdos_off),
	.ay_bdir(o_ay_bdir),
	.ay_bc1(o_ay_bc1),
	.covox_wr(o_covox_wr),
	.beeper_wr(o_beeper_wr),
	.ide_out(o_ide_out),
	.ide_cs0_n(o_ide_cs0_n),
	.ide_cs1_n(o_ide_cs1_n),
	.ide_req(o_ide_req),
	.ide_stall(o_ide_stall),
	.vg_cs_n(o_vg_cs_n),
	.vg_wrFF(o_vg_wrFF),
	.drive_sel(o_drive_sel),
	.sdcs_n(o_sdcs_n),
	.sd2cs_n(o_sd2cs_n),
	.ftcs_n(o_ftcs_n),
	.espcs_n(o_espcs_n),
	.esp_ft_spi_dis(o_esp_ft_spi_dis),
	.spi_mode(o_spi_mode),
	.sd_start(o_sd_start),
	.sd_datain(o_sd_datain),
	.wait_addr(o_wait_addr),
	.wait_start_gluclock(o_wait_start_gluclock),
	.wait_start_comport(o_wait_start_comport),
	.wait_write(o_wait_write)
);

wire [7:0] n_dout;
wire n_dataout;
wire n_porthit;
wire n_external_port;
wire [7:0] n_xt_wr_data;
wire [7:0] n_xt_wr_addr;
wire n_zborder_wr;
wire n_border_wr;
wire n_zvpage_wr;
wire n_vpage_wr;
wire n_vconf_wr;
wire n_gx_offsl_wr;
wire n_gx_offsh_wr;
wire n_gy_offsl_wr;
wire n_gy_offsh_wr;
wire n_t0x_offsl_wr;
wire n_t0x_offsh_wr;
wire n_t0y_offsl_wr;
wire n_t0y_offsh_wr;
wire n_t1x_offsl_wr;
wire n_t1x_offsh_wr;
wire n_t1y_offsl_wr;
wire n_t1y_offsh_wr;
wire n_tsconf_wr;
wire n_palsel_wr;
wire n_tmpage_wr;
wire n_t0gpage_wr;
wire n_t1gpage_wr;
wire n_sgpage_wr;
wire n_hint_beg_wr;
wire n_vint_begl_wr;
wire n_vint_begh_wr;
wire [31:0] n_xt_page;
wire [4:0] n_fmaddr;
wire [7:0] n_sysconf;
wire [7:0] n_memconf;
wire [3:0] n_cacheconf;
wire [7:0] n_fddvirt;
wire [8:0] n_dmaport_wr;
wire [1:0] n_dmawpdev;
wire [7:0] n_intmask;
wire n_vdos_on;
wire n_vdos_off;
wire n_ay_bdir;
wire n_ay_bc1;
wire n_covox_wr;
wire n_beeper_wr;
wire [15:0] n_ide_out;
wire n_ide_cs0_n;
wire n_ide_cs1_n;
wire n_ide_req;
wire n_ide_stall;
wire n_vg_cs_n;
wire n_vg_wrFF;
wire [1:0] n_drive_sel;
wire n_sdcs_n;
wire n_sd2cs_n;
wire n_ftcs_n;
wire n_espcs_n;
wire n_esp_ft_spi_dis;
wire n_spi_mode;
wire n_sd_start;
wire [7:0] n_sd_datain;
wire [7:0] n_wait_addr;
wire n_wait_start_gluclock;
wire n_wait_start_comport;
wire [7:0] n_wait_write;
zports n_dut(
	.zpos(zpos),
	.clk(clk),
	.din(din),
	.a(a),
	.rst(rst),
	.opfetch(opfetch),
	.rd(rd),
	.wr(wr),
	.rdwr(rdwr),
	.iorq(iorq),
	.iorq_s(iorq_s),
	.iord(iord),
	.iord_s(iord_s),
	.iowr(iowr),
	.iowr_s(iowr_s),
	.iordwr(iordwr),
	.iordwr_s(iordwr_s),
	.regs_we(regs_we),
	.cfg_floppy_swap(cfg_floppy_swap),
	.dma_act(dma_act),
	.dos(dos),
	.vdos(vdos),
	.tape_read(tape_read),
	.ide_in(ide_in),
	.ide_stb(ide_stb),
	.ide_ready(ide_ready),
	.keys_in(keys_in),
	.mus_in(mus_in),
	.kj_in(kj_in),
	.vg_intrq(vg_intrq),
	.vg_drq(vg_drq),
	.espcs_in(espcs_in),
	.sd_dataout(sd_dataout),
	.wait_read(wait_read),
	.dout(n_dout),
	.dataout(n_dataout),
	.porthit(n_porthit),
	.external_port(n_external_port),
	.xt_wr_data(n_xt_wr_data),
	.xt_wr_addr(n_xt_wr_addr),
	.zborder_wr(n_zborder_wr),
	.border_wr(n_border_wr),
	.zvpage_wr(n_zvpage_wr),
	.vpage_wr(n_vpage_wr),
	.vconf_wr(n_vconf_wr),
	.gx_offsl_wr(n_gx_offsl_wr),
	.gx_offsh_wr(n_gx_offsh_wr),
	.gy_offsl_wr(n_gy_offsl_wr),
	.gy_offsh_wr(n_gy_offsh_wr),
	.t0x_offsl_wr(n_t0x_offsl_wr),
	.t0x_offsh_wr(n_t0x_offsh_wr),
	.t0y_offsl_wr(n_t0y_offsl_wr),
	.t0y_offsh_wr(n_t0y_offsh_wr),
	.t1x_offsl_wr(n_t1x_offsl_wr),
	.t1x_offsh_wr(n_t1x_offsh_wr),
	.t1y_offsl_wr(n_t1y_offsl_wr),
	.t1y_offsh_wr(n_t1y_offsh_wr),
	.tsconf_wr(n_tsconf_wr),
	.palsel_wr(n_palsel_wr),
	.tmpage_wr(n_tmpage_wr),
	.t0gpage_wr(n_t0gpage_wr),
	.t1gpage_wr(n_t1gpage_wr),
	.sgpage_wr(n_sgpage_wr),
	.hint_beg_wr(n_hint_beg_wr),
	.vint_begl_wr(n_vint_begl_wr),
	.vint_begh_wr(n_vint_begh_wr),
	.xt_page(n_xt_page),
	.fmaddr(n_fmaddr),
	.sysconf(n_sysconf),
	.memconf(n_memconf),
	.cacheconf(n_cacheconf),
	.fddvirt(n_fddvirt),
	.dmaport_wr(n_dmaport_wr),
	.dmawpdev(n_dmawpdev),
	.intmask(n_intmask),
	.vdos_on(n_vdos_on),
	.vdos_off(n_vdos_off),
	.ay_bdir(n_ay_bdir),
	.ay_bc1(n_ay_bc1),
	.covox_wr(n_covox_wr),
	.beeper_wr(n_beeper_wr),
	.ide_out(n_ide_out),
	.ide_cs0_n(n_ide_cs0_n),
	.ide_cs1_n(n_ide_cs1_n),
	.ide_req(n_ide_req),
	.ide_stall(n_ide_stall),
	.vg_cs_n(n_vg_cs_n),
	.vg_wrFF(n_vg_wrFF),
	.drive_sel(n_drive_sel),
	.sdcs_n(n_sdcs_n),
	.sd2cs_n(n_sd2cs_n),
	.ftcs_n(n_ftcs_n),
	.espcs_n(n_espcs_n),
	.esp_ft_spi_dis(n_esp_ft_spi_dis),
	.spi_mode(n_spi_mode),
	.sd_start(n_sd_start),
	.sd_datain(n_sd_datain),
	.wait_addr(n_wait_addr),
	.wait_start_gluclock(n_wait_start_gluclock),
	.wait_start_comport(n_wait_start_comport),
	.wait_write(n_wait_write)
);

wire [199:0] o_all = {o_dout, o_dataout, o_porthit, o_external_port, o_xt_wr_data, o_xt_wr_addr, o_zborder_wr, o_border_wr, o_zvpage_wr, o_vpage_wr, o_vconf_wr, o_gx_offsl_wr, o_gx_offsh_wr, o_gy_offsl_wr, o_gy_offsh_wr, o_t0x_offsl_wr, o_t0x_offsh_wr, o_t0y_offsl_wr, o_t0y_offsh_wr, o_t1x_offsl_wr, o_t1x_offsh_wr, o_t1y_offsl_wr, o_t1y_offsh_wr, o_tsconf_wr, o_palsel_wr, o_tmpage_wr, o_t0gpage_wr, o_t1gpage_wr, o_sgpage_wr, o_hint_beg_wr, o_vint_begl_wr, o_vint_begh_wr, o_xt_page, o_fmaddr, o_sysconf, o_memconf, o_cacheconf, o_fddvirt, o_dmaport_wr, o_dmawpdev, o_intmask, o_vdos_on, o_vdos_off, o_ay_bdir, o_ay_bc1, o_covox_wr, o_beeper_wr, o_ide_out, o_ide_cs0_n, o_ide_cs1_n, o_ide_req, o_ide_stall, o_vg_cs_n, o_vg_wrFF, o_drive_sel, o_sdcs_n, o_sd2cs_n, o_ftcs_n, o_espcs_n, o_esp_ft_spi_dis, o_spi_mode, o_sd_start, o_sd_datain, o_wait_addr, o_wait_start_gluclock, o_wait_start_comport, o_wait_write};
wire [199:0] n_all = {n_dout, n_dataout, n_porthit, n_external_port, n_xt_wr_data, n_xt_wr_addr, n_zborder_wr, n_border_wr, n_zvpage_wr, n_vpage_wr, n_vconf_wr, n_gx_offsl_wr, n_gx_offsh_wr, n_gy_offsl_wr, n_gy_offsh_wr, n_t0x_offsl_wr, n_t0x_offsh_wr, n_t0y_offsl_wr, n_t0y_offsh_wr, n_t1x_offsl_wr, n_t1x_offsh_wr, n_t1y_offsl_wr, n_t1y_offsh_wr, n_tsconf_wr, n_palsel_wr, n_tmpage_wr, n_t0gpage_wr, n_t1gpage_wr, n_sgpage_wr, n_hint_beg_wr, n_vint_begl_wr, n_vint_begh_wr, n_xt_page, n_fmaddr, n_sysconf, n_memconf, n_cacheconf, n_fddvirt, n_dmaport_wr, n_dmawpdev, n_intmask, n_vdos_on, n_vdos_off, n_ay_bdir, n_ay_bc1, n_covox_wr, n_beeper_wr, n_ide_out, n_ide_cs0_n, n_ide_cs1_n, n_ide_req, n_ide_stall, n_vg_cs_n, n_vg_wrFF, n_drive_sel, n_sdcs_n, n_sd2cs_n, n_ftcs_n, n_espcs_n, n_esp_ft_spi_dis, n_spi_mode, n_sd_start, n_sd_datain, n_wait_addr, n_wait_start_gluclock, n_wait_start_comport, n_wait_write};

integer errors = 0, checks = 0, port_wrs = 0, ide_wrs = 0;
task automatic check;
	input [199:0] o, n;
	integer k;
	begin
		checks = checks + 1;
		if (o !== n) begin
			errors = errors + 1;
			if (errors <= 10) begin
				$display("%t ERROR: outputs differ", $time);
				for (k = 0; k < 200; k = k + 1)
					if (o[k] !== n[k]) $display("    bit %0d: old %b new %b", k, o[k], n[k]);
			end
		end
	end
endtask

// every output after both edges (zclk changes at the falling one)
always @(negedge clk) #1 check(o_all, n_all);
always @(posedge clk) #1 check(o_all, n_all);
always @(negedge clk) if (zpos) begin
	if (n_dut.port_wr) port_wrs = port_wrs + 1;
	if (n_dut.port_wr && (a[7:0] == 8'h10 || a[7:0] == 8'h11)) ide_wrs = ide_wrs + 1;
end

initial begin
	repeat (CLOCKS) @(negedge clk);
	$display("tb_eq_zports: %0d checks, %0d port writes (%0d to #10 / #11)", checks, port_wrs, ide_wrs);
	if (port_wrs < 1000 || ide_wrs < 100) begin
		errors = errors + 1;
		$display("ERROR: too few port writes, the test does not test");
	end
	$display("tb_eq_zports: %0d errors", errors);
	$finish;
end

endmodule
