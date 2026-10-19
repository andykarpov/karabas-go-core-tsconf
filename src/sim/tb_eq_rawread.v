`timescale 1ns / 1ps

// vg93_read_path with the catcher on sysclk (SYNC_RAWREAD 1) against the one clocked by the /RAWREAD pin
// (SYNC_RAWREAD 0, the chip), with /RAWREAD made as hrdy_fdc makes it: the AND of two flip-flops of FDC_RDATA on
// clk_8 (a pulse of one clock at a falling edge of the data), RCLK a flip-flop that toggles every 4 to 6 clocks;
// the controls of the decoder random. The latches of the half cells (caught*_q, raw_lat*) and every output are
// compared after every clock. Ends with "tb_eq_rawread: N errors".

module tb_eq_rawread;

parameter CLOCKS = 2000000;

reg sysclk = 1'b0;
always #62.5 sysclk = ~sysclk; // clk_8

integer seed = 5;

// FDC_RDATA: low pulses of 1 to 4 clocks, 2 to 12 clocks apart; rd_reg / rawread as in hrdy_fdc.v
reg fdc_rdata = 1'b1;
reg [1:0] rd_reg = 2'b11;
integer gap = 0;
always @(posedge sysclk) begin
	rd_reg <= {rd_reg[0], fdc_rdata};
	if (gap > 0)
		gap <= gap - 1;
	else begin
		fdc_rdata <= ~fdc_rdata;
		gap <= fdc_rdata ? (1 + ($random(seed) & 3)) : (2 + ($random(seed) % 11 + 11) % 11);
	end
end
wire rawread_n = ~(~rd_reg[1] & rd_reg[0]);
wire rawread_pin = !rawread_n;

// RCLK: a flip-flop of the data separator, sampled once more for rclk_q (vg93_top)
reg rclk = 1'b0;
integer rcnt = 0;
always @(posedge sysclk) begin
	if (rcnt == 0) begin
		rclk <= ~rclk;
		rcnt <= 3 + ($random(seed) % 3 + 3) % 3;
	end
	else
		rcnt <= rcnt - 1;
end
reg rclk_q = 1'b0, rawread_q = 1'b0;
always @(posedge sysclk) begin
	rclk_q <= rclk;
	rawread_q <= rawread_pin;
end

// controls: change at the falling clock
reg cell_ends = 1'b0, word_ends = 1'b0, second_half = 1'b0, cell_window = 1'b0, mfm = 1'b1, mr_s = 1'b0, mr_next = 1'b0;
reg read_enable = 1'b1, det_a1_en = 1'b1, det_fm_mark_en = 1'b0, det_trans_en = 1'b1, det_read_am_en = 1'b0;
reg set_rg = 1'b0, clr_rg = 1'b0;
reg [31:0] r;
always @(negedge sysclk) begin
	r = $random(seed);
	cell_ends <= (r[2:0] == 3'd0);
	word_ends <= (r[6:3] == 4'd0);
	second_half <= r[7] ? ~second_half : second_half;
	cell_window <= r[8];
	if (r[20:12] == 0) mfm <= ~mfm;
	mr_s <= (r[30:21] == 0);
	mr_next <= (r[30:21] == 1);
	if (r[11:9] == 0) begin
		read_enable <= r[13]; det_a1_en <= r[14]; det_fm_mark_en <= r[15]; det_trans_en <= r[16];
		det_read_am_en <= r[17];
	end
	set_rg <= (r[24:19] == 0);
	clr_rg <= (r[24:19] == 1);
end

`define DUT(name, sync) \
	wire name``_clock_cell, name``_dec_data_cell, name``_preamble, name``_any_mark, name``_rd_data, name``_rg_pin, name``_vfoe; \
	vg93_read_path #(.SYNC_RAWREAD(sync)) name( \
		.sysclk(sysclk), .cell_ends(cell_ends), .word_ends(word_ends), .second_half(second_half), \
		.cell_window(cell_window), .mfm(mfm), .mr_s(mr_s), .mr_next(mr_next), .rclk_q(rclk_q), \
		.rawread_pin(rawread_pin), .rclk_pin(rclk), .rawread_q(rawread_q), .read_enable(read_enable), \
		.det_a1_en(det_a1_en), .det_fm_mark_en(det_fm_mark_en), .det_trans_en(det_trans_en), \
		.det_read_am_en(det_read_am_en), .set_rg(set_rg), .clr_rg(clr_rg), \
		.clock_cell(name``_clock_cell), .dec_data_cell(name``_dec_data_cell), .preamble(name``_preamble), \
		.any_mark(name``_any_mark), .rd_data(name``_rd_data), .rg_pin(name``_rg_pin), .vfoe_seen(name``_vfoe));
`DUT(pin, 0)
`DUT(syn, 1)

wire [12:0] pin_v = {pin.caught0_q, pin.caught1_q, pin.raw_lat0, pin.raw_lat1, pin_clock_cell, pin_dec_data_cell,
	pin_preamble, pin_any_mark, pin_rd_data, pin_rg_pin, pin_vfoe};
wire [12:0] syn_v = {syn.caught0_q, syn.caught1_q, syn.raw_lat0, syn.raw_lat1, syn_clock_cell, syn_dec_data_cell,
	syn_preamble, syn_any_mark, syn_rd_data, syn_rg_pin, syn_vfoe};

integer errors = 0, checks = 0, pulses = 0, transitions = 0;
task automatic check;
	input [12:0] a, b;
	begin
		checks = checks + 1;
		if (a !== b) begin
			errors = errors + 1;
			if (errors <= 10) $display("%t ERROR: pin %b sync %b", $time, a, b);
		end
	end
endtask

reg prev_raw = 1'b0;
always @(negedge sysclk) begin
	check(pin_v, syn_v);
	if (rawread_pin && !prev_raw) pulses = pulses + 1;
	prev_raw <= rawread_pin;
	if (pin.caught0_q[0] != pin.caught0_q[1] || pin.caught1_q[0] != pin.caught1_q[1]) transitions = transitions + 1;
end

initial begin
	repeat (CLOCKS) @(negedge sysclk);
	$display("tb_eq_rawread: %0d checks, %0d /RAWREAD pulses, %0d transitions caught", checks, pulses, transitions);
	if (pulses < 1000 || transitions < 1000) begin
		errors = errors + 1;
		$display("ERROR: too few pulses, the test does not test");
	end
	$display("tb_eq_rawread: %0d errors", errors);
	$finish;
end

endmodule
