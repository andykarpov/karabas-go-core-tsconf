// Floppy drive glue of hrdy_fdc: a digital data separator for the read side and the write precompensation for the
// write side, on SYSCLK of the VG93 model (clk_bus: 28 MHz, 24 MHz in the DS80 mode), one step per clock.
// After epm570/fdd_glue.v of github.com/demyanenko-d/FD1793_1818VG93 (CE_HALF = 0, HALF = 56 at 28 MHz as on its
// DE1 build), with the RCLK half period chosen by ds80 at run time: 56 steps at 28 MHz, 48 at 24 MHz (2 us).
// Credit there: the DPLL algorithm after fapch_zek by ZEK (ZX-Evolution, pentevo/fpga/current/vg93), the
// precompensation after the same vg93.v.
//
// Read: /RDATA is synchronised and filtered (a level must hold two samples), its falling edge is one flux
// transition: /RAWREAD, one SYSCLK (VG93_FAST_SYSCLK samples it every SYSCLK). RCLK is a free running square wave
// of HALF steps per half period (one MFM channel bit at 250 kbit/s); on every transition the phase counter is pulled
// half way to the window centre (cnt <= (cnt + C) / 2), so the separator follows the speed of the disk.
// Write: a WD pulse of the model starts one counter loaded with delay + width; /WDATA is low (registered) while the
// counter is <= the width (6 steps: 213 ns at 28 MHz, 249 ns at 24 MHz). Delay 3 steps nominal; LATE / EARLY move it
// by 1 step outside TG43, by 2 steps inside.
module fdd_glue (
    input  wire clk,                 // SYSCLK, the model's clock
    input  wire ds80,                // 1: clk is 24 MHz, 0: 28 MHz
    input  wire rdata_n,             // /RDATA from the drive
    output reg  rclk = 1'b0,         // to the model: RCLK
    output wire rawread_n,           // to the model: /RAWREAD
    input  wire wd, early, late, tg43,   // from the model (same clock)
    output reg  wdata_n = 1'b1       // /WDATA to the drive
);
    wire [5:0] half_end = ds80 ? 6'd47 : 6'd55;    // HALF - 1
    wire [5:0] centre   = ds80 ? 6'd23 : 6'd27;    // HALF / 2 - 1

    // ---- separator ----
    reg [2:0] rs = 3'b111;           // input synchroniser
    reg rd = 1'b1, rd_d = 1'b1;      // filtered level
    always @(posedge clk) begin
        rs <= {rs[1:0], rdata_n};
        if (rs[2:1] == 2'b00 || rs[2:1] == 2'b11) rd <= rs[2];
        rd_d <= rd;
    end
    wire pulse = rd_d && !rd;        // falling edge of /RDATA, one step
    assign rawread_n = !pulse;
    reg [5:0] cnt = 6'd0;            // phase in the RCLK half period, 0..HALF-1
    wire [6:0] pull = {1'b0, cnt} + {1'b0, centre};  // (cnt + C) / 2: half way to the centre
    always @(posedge clk) begin
        if (pulse) cnt <= pull[6:1];
        else if (cnt == half_end) begin cnt <= 6'd0; rclk <= !rclk; end
        else cnt <= cnt + 6'd1;
    end

    // ---- write precompensation: one counter, load = delay + width, /WDATA while counter <= width ----
    reg wd_d = 1'b0;
    always @(posedge clk) wd_d <= wd;
    wire wd_start = wd && !wd_d;
    reg [3:0] pc = 4'd0;
    always @(posedge clk) begin
        if (wd_start)
            case ({late, tg43, early})
            3'b110:  pc <= 4'd11;    // late, inner tracks: delay 5
            3'b100:  pc <= 4'd10;    // late: 4
            3'b011:  pc <= 4'd7;     // early, inner tracks: 1
            3'b001:  pc <= 4'd8;     // early: 2
            default: pc <= 4'd9;     // nominal: 3 steps delay + 6 steps pulse
            endcase
        else if (pc != 4'd0) pc <= pc - 4'd1;
        wdata_n <= !(pc != 4'd0 && pc <= 4'd6);
    end
endmodule
