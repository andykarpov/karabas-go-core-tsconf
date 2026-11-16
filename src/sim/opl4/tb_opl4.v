`timescale 1ns / 1ps
/*
 tb_opl4 (iverilog): the OPL4 of the core as tsconf.v and the tops wire it: opl4_kg (the wave part on
 clk_sys, the bus of a Z80 on clk_bus at 14 MHz), its sample memory through port 2 of gs_top (the GS
 cpu idle: t80s_stub) and sdram2p into sdram_model (CL 3, timing checks). The FM part is a stub (it is
 opl3_fpga as it is, checked against Nuked-OPL3 in u16_tsconf_gs_v24).
 First the FL loader writes 256 bytes of the ROM (n xor #A5) at 250 ns a byte, the OPL4 held
 (fl_act); then the Z80 runs opl4_z80.asm (see there) and the results are checked, with the IRQ of the
 FM timer (one rising edge, down after its reset).
 Prints "tb_opl4: 0 errors".
*/
module tb_opl4;
parameter integer INTERP = 1;   // the interpolation of opl4.v (the frame time: 24 voices fetch two samples each)

localparam real T = 11.892;   // clk_sys 84.09 MHz

reg clk = 1'b0;
always #(T / 2) clk = ~clk;
reg clk_bus = 1'b0;
integer div = 0;
always @(posedge clk) begin
	div = (div + 1) % 3;
	if (div == 0) clk_bus <= 1'b1;
	if (div == 1) clk_bus <= 1'b0;
end
reg ce_14m = 1'b0;
always @(posedge clk_bus) ce_14m <= !ce_14m;

reg areset = 1'b1;
reg cpu_reset = 1'b1;
reg fl_act = 1'b0, fl_wr = 1'b0;
reg [31:0] fl_a = 32'd0;
reg [7:0] fl_d = 8'd0;

// the Z80 and its RAM
wire m1_n, mreq_n, iorq_n, rd_n, wr_n, halt_n;
wire [15:0] A;
wire [7:0] dout;
reg [7:0] ram [0:65535];
wire [7:0] odo;
wire osel;
// the read data of the OPL4 through a clk_bus register, as tsconf.v has it (opl4_do_r)
reg [7:0] odo_r = 8'hff;
always @(posedge clk_bus) odo_r <= odo;
wire [7:0] di = (!mreq_n && !rd_n) ? ram[A] : (osel && !rd_n) ? odo_r : 8'hff;
always @(posedge clk_bus) if (!mreq_n && !wr_n) ram[A] <= dout;
tv80s_cen cpu(.cen(ce_14m), .reset_n(!cpu_reset), .clk(clk_bus), .wait_n(1'b1), .int_n(1'b1), .nmi_n(1'b1),
	.busrq_n(1'b1), .m1_n(m1_n), .mreq_n(mreq_n), .iorq_n(iorq_n), .rd_n(rd_n), .wr_n(wr_n), .rfsh_n(),
	.halt_n(halt_n), .busak_n(), .A(A), .di(di), .dout(dout));

// the OPL4 (its reset into clk as in tsconf.v)
reg [1:0] opl4_rst_s = 2'b11;
always @(posedge clk) opl4_rst_s <= {opl4_rst_s[0], cpu_reset | fl_act};
wire [21:0] m_addr;
wire m_req, m_we, m_ack;
wire [7:0] m_wdata;
wire [15:0] m_rdata;
wire [15:0] out_l, out_r;
wire irq;
// the FM timer IRQ (to /INT in tsconf.v): its rising edges
integer irq_rise = 0;
reg irq_q = 1'b0;
always @(posedge clk) begin irq_q <= irq; if (irq && !irq_q) irq_rise = irq_rise + 1; end

opl4_kg opl4 (
	.CLK(clk), .CLK28(clk_bus), .RESET(opl4_rst_s[1]),
	.A(A[7:0]), .DI(dout), .DO(odo), .IORQ_n(iorq_n), .M1_n(m1_n), .RD_n(rd_n), .WR_n(wr_n), .DOS(1'b0), .INTERP(INTERP != 0),
	.SEL(osel), .IRQ(irq),
	.MEM_ADDR(m_addr), .MEM_REQ(m_req), .MEM_WE(m_we), .MEM_WDATA(m_wdata), .MEM_ACK(m_ack), .MEM_RDATA(m_rdata),
	.OUT_L(out_l), .OUT_R(out_r)
);

wire [15:0] dq;
wire [12:0] sa;
wire [1:0] ba, dqm;
wire nwe, nras, ncas, sclk;

gs_top gs_top (
	.clk_sys(clk), .clk_bus(clk_bus), .ce(ce_14m), .reset(1'b1), .areset(areset),
	.a(16'hFFFF), .di(8'hFF), .mreq_n(1'b1), .iorq_n(1'b1), .m1_n(1'b1), .rd_n(1'b1), .wr_n(1'b1),
	.oe(), .do_bus(),
	.sdram_clk(sclk), .sdram_dq(dq), .sdram_a(sa), .sdram_dqm(dqm), .sdram_ba(ba),
	.sdram_we_n(nwe), .sdram_ras_n(nras), .sdram_cas_n(ncas),
	.loader_act(1'b0), .loader_a(32'd0), .loader_d(8'd0), .loader_wr(1'b0),
	.fl_wr(fl_wr), .fl_a(fl_a), .fl_d(fl_d),
	.opl_addr(m_addr), .opl_req(m_req), .opl_we(m_we), .opl_wdata(m_wdata), .opl_ack(m_ack), .opl_rdata(m_rdata),
	.out_l(), .out_r()
);

// 12 row bits: the RAM of the OPL4 (byte 200000 = row 800) apart from its ROM (row 0)
sdram_model #(.CLK_NS(T), .CL(3), .ROW_BITS(12)) sdr (
	.clk(clk), .ba(ba), .a(sa), .dqm(dqm), .ras_n(nras), .cas_n(ncas), .we_n(nwe), .dq(dq)
);


// the engine of opl4.v: the clocks of a frame (E_START .. back to E_IDLE) and the ticks it lost (a tick while
// the one before still waits): 24 voices must fit a period of 44.1 kHz (1907 clk_sys)
integer fr_clk = 0, fr_max = 0, fr_n = 0, fr_sum = 0, lost = 0, st_fetch = 0, st_gap = 0, st_other = 0, voices = 0, fallback = 0;
reg fr_on = 1'b0;
always @(posedge clk) begin
	if (opl4.core.estate == 5'd2) begin fr_on <= 1'b1; fr_clk = 0; end
	else if (fr_on && opl4.core.estate == 5'd1) begin
		fr_on <= 1'b0; fr_n = fr_n + 1; fr_sum = fr_sum + fr_clk;
		if (fr_clk > fr_max) fr_max = fr_clk;
	end
	if (fr_on) begin
		fr_clk = fr_clk + 1;
		if (opl4.core.estate == 5'd7) begin voices = voices + 1; if (opl4.core.interp && opl4.core.late) fallback = fallback + 1; end
		if (opl4.core.estate == 5'd8) st_fetch = st_fetch + 1;
		else if (opl4.core.estate == 5'd20) st_gap = st_gap + 1;
		else st_other = st_other + 1;
	end
	if (opl4.core.sample_tick && opl4.core.tick_pend && opl4.core.estate != 5'd1) lost = lost + 1;
end

integer errors = 0;
integer i;
task check(input [8*24-1:0] what, input [15:0] got, input [15:0] exp);
	begin
		if (got !== exp) begin
			errors = errors + 1;
			$display("tb_opl4: %0s: %h, expected %h", what, got, exp);
		end
	end
endtask

initial begin
	for (i = 0; i < 65536; i = i + 1) ram[i] = 8'h00;
	$readmemh("opl4_z80.hex", ram);
	repeat (20) @(posedge clk);
	areset = 1'b0;
	wait (!gs_top.sdram.init);
	// the ROM from the FL item, the OPL4 held
	@(posedge clk_bus);
	fl_act <= 1'b1;
	for (i = 0; i < 256; i = i + 1) begin
		@(posedge clk_bus);
		fl_a <= i; fl_d <= i[7:0] ^ 8'hA5; fl_wr <= 1'b1;
		@(posedge clk_bus);
		fl_wr <= 1'b0;
		repeat (5) @(posedge clk_bus);
	end
	repeat (10) @(posedge clk_bus);
	fl_act <= 1'b0;
	repeat (10) @(posedge clk_bus);
	cpu_reset <= 1'b0;
	wait (ram[16'h8007] == 8'hEE || $time > 100_000_000);
	check("done", ram[16'h8007], 16'h00EE);
	check("ID before NEW2", ram[16'h8000], 16'h0006);
	check("ID after NEW2", ram[16'h8001], 16'h0002);
	check("reg 2", ram[16'h8002], 16'h0030);
	check("RAM test AA", ram[16'h8003], 16'h00AA);
	check("RAM test 55", ram[16'h8004], 16'h0055);
	check("upload errors", {ram[16'h8006], ram[16'h8005]}, 16'h0000);
	check("ROM errors", {ram[16'h8009], ram[16'h8008]}, 16'h0000);
	check("timer status", ram[16'h800A], 16'h00C0);
	check("timer reset", ram[16'h800B], 16'h0000);
	check("FM reg read bank 0", ram[16'h800C], 16'h005A);
	check("FM reg read bank 1", ram[16'h800D], 16'h00A5);
	check("FM reg read other bank", ram[16'h800E], 16'h0000);
	check("IRQ edges", irq_rise, 16'd1);
	check("IRQ at the end", irq, 16'd0);
	if (sdr.errors != 0) begin
		errors = errors + sdr.errors;
		$display("tb_opl4: %0d errors of the SDRAM model", sdr.errors);
	end
	$display("tb_opl4: engine: %0d frames, %0d clocks each at most, %0d on average (of 1907), %0d ticks lost (a frame: fetch %0d, gap %0d, other %0d)", fr_n, fr_max, fr_n ? fr_sum / fr_n : 0, lost,
		fr_n ? st_fetch / fr_n : 0, fr_n ? st_gap / fr_n : 0, fr_n ? st_other / fr_n : 0);
	$display("tb_opl4: interpolation: %0d of %0d voice samples without it (the frame late)", fallback, voices);
	if (lost != 0) begin errors = errors + 1; $display("tb_opl4: the engine lost ticks"); end
	$display("tb_opl4: done at %0.0f us", $realtime / 1000.0);
	$display("tb_opl4: %0d errors", errors);
	$finish;
end

endmodule
