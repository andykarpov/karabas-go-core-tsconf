// The start of the VGA picture of the Go: black and no syncs while `hold` (the PLL not locked or the
// firmware still in the INIT of the core) and FRAMES frames after it, then the picture from the start
// of a vsync pulse, so the monitor sees a clean loss of the signal after boot.kg (800x600) and then
// only whole frames of 576p. A TV (Bravis, MStar) showed the picture shifted after every core start
// until its H-Pos was moved and back (backlog 2026-11-17); this is the attempt at a clean start.
// The syncs are high active (video_sync.v); everything is one clk later (all signals alike).

module vga_start_hold #(
	parameter FRAMES = 32
)(
	input  wire        clk,
	input  wire        hold,
	input  wire [23:0] rgb_i,
	input  wire        hs_i,
	input  wire        vs_i,
	input  wire        de_i,
	output reg  [23:0] rgb_o = 24'd0,
	output reg         hs_o = 1'b0,
	output reg         vs_o = 1'b0,
	output reg         de_o = 1'b0,
	output reg         run = 1'b0
);

reg vs_d = 1'b0;
reg [5:0] cnt = 6'd0;

wire vs_rise = vs_i & ~vs_d;
wire last = (cnt == FRAMES - 1);
wire on = ~hold & (run | (vs_rise & last));  // the clock of the first vsync goes out already

always @(posedge clk) begin
	vs_d <= vs_i;
	if (hold) begin
		cnt <= 6'd0;
		run <= 1'b0;
	end else if (~run & vs_rise) begin
		if (last)
			run <= 1'b1;
		else
			cnt <= cnt + 6'd1;
	end
	rgb_o <= on ? rgb_i : 24'd0;
	hs_o  <= hs_i & on;
	vs_o  <= vs_i & on;
	de_o  <= de_i & on;
end

endmodule
