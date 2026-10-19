`timescale 1ns / 1ps

// saa1099 on clk_bus with the 8 MHz clock enable (rtl/sound/saa1099.v) against the version on its own clock
// (sim/ref/saa1099_ref.v, the old one on clk8): the old one gets a clock that rises at the edges of clk_bus with
// ce_8, so both see the same edges. CPU writes as tsconf.v makes them (wr_n low for a whole I/O cycle, several
// clocks), random registers and data, a reset now and then; out_l / out_r compared after every clock (not around
// a reset, see below).
// Ends with "tb_eq_saa: N errors".

module tb_eq_saa;

parameter CLOCKS = 3000000;

reg clk = 1'b0;
always #17.84 clk = ~clk; // 28.03 MHz

// the clock enable of tsconf.v
reg [16:0] acc8 = 17'd0;
always @(posedge clk)
	acc8 <= {1'b0, acc8[15:0]} + 17'd18704;
wire ce_8 = acc8[16];

// the clock of the old one: rises at the edges of clk with ce_8 (ce_8 is never high two clocks in a row)
reg clk_old = 1'b0;
always @(posedge clk)
	clk_old <= ce_8;

// stimulus, changing at the falling clock
reg rst_n = 1'b0, wr_n = 1'b1, a0 = 1'b0;
reg [7:0] din = 8'd0;
wire [7:0] old_l, old_r, new_l, new_r;

saa1099ref old_dut(.clk(clk_old), .rst_n(rst_n), .cs_n(1'b0), .a0(a0), .wr_n(wr_n), .din(din),
	.out_l(old_l), .out_r(old_r));
saa1099 new_dut(.clk(clk), .ena(ce_8), .rst_n(rst_n), .cs_n(1'b0), .a0(a0), .wr_n(wr_n), .din(din),
	.out_l(new_l), .out_r(new_r));

integer errors = 0, checks = 0, changes = 0;
task automatic check;
	input [7:0] o_l, o_r, n_l, n_r;
	begin
		checks = checks + 1;
		if (o_l !== n_l || o_r !== n_r) begin
			errors = errors + 1;
			if (errors <= 10)
				$display("%t ERROR: out old %h %h new %h %h", $time, o_l, o_r, n_l, n_r);
		end
	end
endtask

// not compared while rst_n is low and 4 clocks after: the reset of the new one acts at every clock, of the old one
// at its 8 MHz edges, so the new one mutes its output (ctrl = 0) up to one 8 MHz period earlier and comes out of
// it with the same state at the same edge
reg [15:0] prev_out = 16'd0;
reg rst_seen = 1'b0;
integer after_rst = 0;
always @(negedge clk) begin
	if (!rst_n) begin
		rst_seen <= 1'b1;
		after_rst = 0;
	end
	else if (after_rst < 4)
		after_rst = after_rst + 1;
	if (rst_n && rst_seen && after_rst >= 4)
		check(old_l, old_r, new_l, new_r);
	if ({new_l, new_r} != prev_out) changes = changes + 1;
	prev_out <= {new_l, new_r};
end

integer seed = 7, i, gap, len;
// a write: address or data, wr_n low for len clocks
task automatic cpu_write;
	input addr;
	input [7:0] d;
	input integer low;
	integer k;
	begin
		@(negedge clk);
		a0 = addr; din = d; wr_n = 1'b0;
		for (k = 0; k < low; k = k + 1) @(negedge clk);
		wr_n = 1'b1;
		din = $random(seed);
	end
endtask

initial begin
	repeat (20) @(negedge clk);
	rst_n = 1'b1;
	i = 0;
	while (i < CLOCKS) begin
		gap = 4 + ($random(seed) & 63);
		len = 3 + ($random(seed) & 7);   // 3..10 clocks: an I/O cycle at 14 to 3.5 MHz
		repeat (gap) @(negedge clk);
		// registers: amplitudes 00-05, frequencies 08-0D, octaves 10-12, enables 14-15, noise 16, envelopes 18-19,
		// sound enable / reset 1C
		cpu_write(1'b1, ($random(seed) & 8'h1F), len);
		repeat (2 + ($random(seed) & 7)) @(negedge clk);
		cpu_write(1'b0, ((($random(seed) & 15) == 0) ? 8'h01 : $random(seed)), len);
		if (($random(seed) & 1023) == 0) begin // reset now and then
			@(negedge clk) rst_n = 1'b0;
			repeat (5) @(negedge clk);
			rst_n = 1'b1;
		end
		i = i + gap + 2 * len + 8;
	end
	$display("tb_eq_saa: %0d checks, %0d output changes", checks, changes);
	if (changes < 1000) begin
		errors = errors + 1;
		$display("ERROR: the outputs hardly changed, the test does not test");
	end
	$display("tb_eq_saa: %0d errors", errors);
	$finish;
end

endmodule
