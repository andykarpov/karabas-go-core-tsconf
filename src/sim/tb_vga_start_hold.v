// vga_start_hold: black and no syncs while hold and FRAMES frames after it, then the picture from the
// start of a vsync pulse (a whole pulse), every signal one clk late, and a hold again blanks at once.
// iverilog -o tb tb_vga_start_hold.v ../rtl/vga_start_hold.v && vvp tb
`timescale 1ns/1ps
module tb_vga_start_hold;

localparam LINE = 20, LINES = 10, VS_LINES = 2, FRAMES = 4;

reg clk = 0;
always #5 clk = ~clk;

reg hold = 1;
reg [15:0] t = 0;
always @(posedge clk) t <= t + 1'd1;
wire [7:0] h = t % LINE;
wire [7:0] v = (t / LINE) % LINES;
wire hs_i = (h < 3);
wire vs_i = (v >= 3) && (v < 3 + VS_LINES);
wire de_i = (h >= 5) && (v >= 6);
wire [23:0] rgb_i = {8'd0, t[7:0], 8'hA5};

wire [23:0] rgb_o;
wire hs_o, vs_o, de_o, run;

vga_start_hold #(.FRAMES(FRAMES)) dut(
	.clk(clk), .hold(hold), .rgb_i(rgb_i), .hs_i(hs_i), .vs_i(vs_i), .de_i(de_i),
	.rgb_o(rgb_o), .hs_o(hs_o), .vs_o(vs_o), .de_o(de_o), .run(run));

integer errors = 0, rises = 0, out_vs_rises = 0, first_out = -1, released = 0;
reg [23:0] rgb_p; reg hs_p, vs_p, de_p, vs_pp, vs_op;

always @(posedge clk) begin
	// the release: the first vsync out = a vsync start of the input one clk earlier
	if (vs_o && !vs_op && !released) begin
		released = 1;
		first_out = t;
		if (!(vs_p && !vs_pp)) begin errors = errors + 1; $display("release not at a vsync start"); end
		if (rises != FRAMES) begin errors = errors + 1; $display("released after %0d frames", rises); end
	end
	// after it the previous input, before it nothing
	if (released) begin
		if ({rgb_o, hs_o, vs_o, de_o} !== {rgb_p, hs_p, vs_p, de_p}) begin
			errors = errors + 1;
			if (errors < 5) $display("mismatch at %0d", t);
		end
	end else if (rgb_o !== 24'd0 || hs_o || vs_o || de_o) begin
		errors = errors + 1;
		if (errors < 5) $display("output while held at %0d", t);
	end
	if (vs_i && !vs_p && !hold) rises = rises + 1;
	rgb_p <= rgb_i; hs_p <= hs_i; vs_p <= vs_i; de_p <= de_i; vs_pp <= vs_p; vs_op <= vs_o;
end

initial begin
	rgb_p = 0; hs_p = 0; vs_p = 0; de_p = 0; vs_pp = 0; vs_op = 0;
	// hold over a few frames, let go in the middle of a vsync pulse (it must not count)
	#(10 * LINE * LINES * 3 + 10 * LINE * 4);
	@(negedge clk) hold = 0;
	#(10 * LINE * LINES * (FRAMES + 3));
	if (!released) begin errors = errors + 1; $display("never released"); end
	// a hold again: black at once (one clk later)
	@(negedge clk) hold = 1;
	@(posedge clk); #1;
	released = 0;
	if (run) begin errors = errors + 1; $display("run stays after hold"); end
	#(10 * LINE * LINES);
	$display("tb_vga_start_hold: %0d errors", errors);
	$finish;
end

endmodule
