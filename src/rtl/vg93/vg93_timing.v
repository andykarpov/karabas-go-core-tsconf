// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// Timing of the chip: when a microword ends, when its second half runs, when a bit cell of the disk ends.
// The other blocks see only the outputs of this module.
//
// What the blocks see (each level holds for one SYSCLK cycle; the event happens at the SYSCLK edge ending it):
//   cell_ends    a bit cell of the disk ends: the channel bit is taken, the write encoder steps half a cell
//   word_ends    the microword ends: state takes its next value, the next microword is fetched. With cell_ends in
//                the same cycle the cell ends first (the word sees the new channel bit)
//   second_half  the second half of the microword: its results are visible outside (status, pins, host reads)
//                and the requests it raises (DRQ, interrupt) act. At a word end it is always 1, except for the
//                power-on edge; so "x <= second_half ? x_next : x" at a word end loads x_next, and keeps x at
//                power-on. In read mode the second half has no length: it is the cycle in which the word ends
//   second_half_held  the second half has lasted since an earlier cycle (not in read mode): latches that follow
//                the word in its first half (PC + n, the INTRQ pin) hold
//   write_window the part of the cell in which WD may pulse; cell_window also counts the zero-length window of a
//                read mode cell end (the mark latch of the read path)
//   power_on     the power-on edge: a cell end and a word end for every block (the k = 0 line of the trace)
// The schematic calls these F1 / F2: the F1 rise = word end, F1 low = second half, the F2 rise = cell end, F2 low
// = write window (docs/behav_map.md).
//
// Outside read mode the divider U4 times words and cells. U4 counts CLK rises; one MFM microword (FM: double):
//   CLK rise         :   1     2     3     0      (U4 after the rise; FM: 1..7, 0)
//   CLK              : _/‾\_/‾\_/‾\_/‾\_/
//   cell ends        :       ^           ^      at a rise from an odd count (FM: from 3, 7)
//   write window     :    [_]         [_]       CLK low after an odd count (FM: the whole CLK period after 3, 7)
//   second half      :             [=====]      from the rise to count 3 (FM: 7) to the word end
//   word ends        :                   ^      at the next rise, with a cell end
// so a microword lasts 4 CLK (FM: 8), a cell 2 CLK (FM: 4), and the word end always comes with a cell end.
// In read mode (the last word asked to read the disk - U19 - and RCLK has moved since /MR - U15) every RCLK edge
// ends a cell, and two cells after entering read mode (U20, U21) the RCLK edge on a data cell (the clock window,
// read path) also ends the word: in read mode one microword = one data bit of the disk. The divider then does not
// begin a second half (U16). /MR ends read mode at once (U15 reset); if the divider is in its window or second
// half phase then, that phase begins now.
//
// SYSCLK comes from the oscillator of CLK and RCLK, at least 8 x the highest CLK (16 MHz for a 1 / 2 MHz CLK).
// The pins are sampled once (vg93_top) and an edge is handled one cycle after it is sampled:
//   CLK edge between two SYSCLK edges -> next SYSCLK edge: clk_q takes it -> that cycle: cell_ends / word_ends /
//   second_half for every block -> next SYSCLK edge: the registers take their next values
// so a word ends 1..2 SYSCLK cycles after the CLK or RCLK edge. Within one cycle the events keep the order of the
// C core: /MR, then CLK, then RCLK; a wire *_at_clk is what the CLK edge sees, *_at_rclk what the RCLK edge sees.
`include "vg93_config.vh"
module vg93_timing (
    input  wire sysclk,
    input  wire clk_q, rclk_q, mr_q, dden_q,  // sampled pins (active high)
    input  wire read_enable,                  // the current microword reads the disk (read mode request)
    input  wire clock_cell,                   // the read path: the last cell was a clock cell (U542 = ~CLOCK_WINDOW;
                                              // not yet updated by this edge): an RCLK edge now ends no word
    output wire cell_ends, word_ends, power_on,
    output wire second_half, second_half_held,
    output reg  write_window = 1'b0,
    output wire cell_window,
    output reg  mr_s = 1'b0,                  // MR_S: /MR as the last word ended
    output wire mr_next,                      // the MR_S that this word end takes
    output reg  read_request = 1'b0,          // U19: the last word asked to read the disk
`ifdef VG93_MFM_ONLY
    output wire mfm                           // DDEN_S: constant 1, no DDEN_n pin (the FM logic is removed)
`else
    output reg  mfm = 1'b0                    // DDEN_S: MFM mode as the last word ended
`endif
);
`ifdef VG93_MFM_ONLY
    assign mfm = 1'b1;
`endif
    reg  rclk_since_mr = 1'b0;                // U15: RCLK has moved since /MR
    reg  read_cells1 = 1'b0;                  // U20, U21: read request and RCLK seen one / two cells ago
    reg  read_cells2 = 1'b0;
    reg  [2:0] clk_div = 3'd0;                // U4: position of CLK in the microword
    reg  half2 = 1'b0;                        // the divider's second half runs

    // U4 phases: a cell ends at a rise from this count / the second half begins at a rise to this count
    function cell_phase(input mfm_mode, input [2:0] count);
        cell_phase = mfm_mode ? count[0] : count[1:0] == 2'b11;
    endfunction
    function half2_phase(input mfm_mode, input [2:0] count);
        half2_phase = mfm_mode ? count[1:0] == 2'b11 : count == 3'd7;
    endfunction

    // ---- power-on: cycle 0 samples the pins, cycle 1 is the power-on edge, edges are looked for from cycle 2 on
    // (clk_prev / rclk_prev hold the sampled levels by then: no false edge) ----
    reg  [1:0] power_wait = 2'd0;
    wire powered = power_wait == 2'd2;
    assign power_on = power_wait == 2'd1;

    reg  clk_prev = 1'b0, rclk_prev = 1'b1;
    wire clk_rise = powered && clk_q && !clk_prev;
    wire clk_fall = powered && !clk_q && clk_prev;
    wire rclk_edge = powered && rclk_q != rclk_prev;

    // ---- read mode: /MR first, then the CLK edge, then the RCLK edge ----
    wire rclk_since_mr_at_rclk = mr_q ? 1'b0 : rclk_edge ? 1'b1 : rclk_since_mr;
    wire read_mode_at_clk = read_request && rclk_since_mr && !mr_q;
    wire read_mode_at_rclk = read_request && rclk_since_mr_at_rclk;
    wire read_words = read_cells2 && rclk_since_mr;     // U16: RCLK times the words (U15 as before this /MR)

    // ---- CLK: the divider times words and cells outside read mode ----
    wire divider_counts = clk_rise && !read_mode_at_clk;
    wire [2:0] div_next = clk_div + 3'd1;
    wire cell_ends_clk = divider_counts && cell_phase(mfm, clk_div);
    wire word_ends_clk = divider_counts && half2;
    wire half2_begins = divider_counts && half2_phase(mfm, div_next) && !read_words;
    wire window_opens = (divider_counts && !mfm && cell_phase(1'b0, div_next)) ||
                        (clk_fall && !read_mode_at_clk && mfm && cell_phase(1'b1, clk_div));

    // ---- RCLK in read mode: every edge ends a cell; on a data cell (U17) the word too ----
    wire cell_ends_rclk = rclk_edge && read_mode_at_rclk;
    wire word_ends_rclk = cell_ends_rclk && read_cells2 && rclk_since_mr_at_rclk && !clock_cell;

    // ---- /MR ends read mode: the divider takes over in its current phase (the C core: "if F2 / F1 would be low
    // now, they go low now"); the window uses the CLK level of this cycle ----
    wire mr_ends_read = mr_q && rclk_since_mr && read_request;
    wire mr_window = mr_ends_read && !write_window && (mfm ? !clk_q : 1'b1) && cell_phase(mfm, clk_div);
    wire mr_half2 = mr_ends_read && !half2 && half2_phase(mfm, clk_div);

    assign cell_ends = power_on || cell_ends_clk || cell_ends_rclk;
    assign word_ends = power_on || word_ends_clk || word_ends_rclk;
    assign second_half = half2 || word_ends_rclk;
    assign second_half_held = half2 && !word_ends_rclk;
    assign cell_window = write_window || cell_ends_rclk;
    assign mr_next = mr_q;

    always @(posedge sysclk) begin
        if (!powered) power_wait <= power_wait + 2'd1;
        clk_prev <= clk_q;
        rclk_prev <= rclk_q;
        if (clk_rise) clk_div <= div_next;                       // U4 counts in read mode too
        rclk_since_mr <= rclk_since_mr_at_rclk;

        if (cell_ends) write_window <= 1'b0;
        else if (window_opens || mr_window) write_window <= 1'b1;
        if (word_ends) half2 <= 1'b0;
        else if (half2_begins || mr_half2) half2 <= 1'b1;

        if (word_ends) begin
            read_request <= read_enable;
            mr_s <= mr_q;
`ifndef VG93_MFM_ONLY
            mfm <= dden_q;
`endif
        end
        if (cell_ends) begin
            read_cells1 <= read_request && rclk_since_mr_at_rclk;
            read_cells2 <= read_cells1;
        end
    end
endmodule
