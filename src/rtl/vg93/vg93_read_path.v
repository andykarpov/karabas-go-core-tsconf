// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// Read data path (sheets raw_sampler, am_detector, am_selector, mfm_decoder, part of shared_logic and misc_logic).
//
// A /RAWREAD pulse marks a flux transition: it sets the latch of the half of the RCLK period it falls into (U500
// for RCLK = 0, U511 for RCLK = 1). At every cell end the channel bit of the cell that just ended shifts into the
// 17-bit window AM16..AM0 and its latch resets. The window feeds
//   - the mark detectors, each enabled by the microword that waits for it: MFM A1h (4489h) and C2h (5224h), the
//     sync bytes with a missing clock; the FM marks; and the transition mark 2555h - the junction of the last A1h
//     and the address mark byte that follows it;
//   - the preamble detector (alternating channel bits: 00h / FFh bytes);
//   - the clock window: after a sync mark the data cells are every second channel bit.
// The chip does not compare "A1 A1 A1 FE" as a sequence: the microprogram counts the A1h marks (A1_DET,
// A1_DET_CRC, A1_DET: the CRC preset 968Bh), then waits for the transition mark, then tells the mark type from the
// data bits (RDATA_TST: FCh..FFh ID field, F8h..FBh data, F8h / F9h deleted).
// The MFM decoder takes the data cells into RD_DATA; in read mode one microword is one data bit. RG (read gate)
// and /VFOE (separator enable, pin 33) belong to the read side too: RG is set by SET_RG after the preamble, /VFOE is
// low in read words.
//
// /RAWREAD comes from the drive, asynchronous to everything. U500 / U511 on the chip are set while the pulse is low,
// the latch of the half RCLK is in: so a pulse that is still low when a cell end resets both latches (U504) sets
// its latch again. The model takes the sampled level for that, and for pulses shorter than a SYSCLK cycle a
// catcher flip-flop of the half cell, flipped by the pulse itself (half chosen by RCLK at the pulse); the model sees
// the flip in the next cycle. VG93_FAST_SYSCLK (SYSCLK >= 40 MHz): no catcher, the sampled level only (vg93_top).
//
// Die defect, kept on purpose: the A1h and C2h detectors do not look at channel bit 13 (the comparator input is
// not connected on the die), so 4489h / 5224h also match with that bit flipped. Copy protections rely on it.
// VG93_FD1793_MARKS: the detectors of the WD FD1793 instead, all 16 bits compared (not the default).
`include "vg93_config.vh"
module vg93_read_path (
    input  wire sysclk,
    input  wire cell_ends, word_ends, second_half,
    input  wire cell_window,              // the write window, or the zero-length window of a read mode cell end
    input  wire mfm, mr_s, mr_next,
    input  wire rclk_q,                   // RCLK now (sampled); the bit of the cell that ends is in the latch of the
                                          // other half
    input  wire rawread_pin, rclk_pin,    // /RAWREAD active and RCLK straight from the pins (the catcher; not
                                          // used with VG93_FAST_SYSCLK)
    input  wire rawread_q,                // /RAWREAD active, sampled
    // decoder
    input  wire read_enable, det_a1_en, det_fm_mark_en, det_trans_en, det_read_am_en, set_rg, clr_rg,
    output reg  clock_cell = 1'b0,        // U542 = ~CLOCK_WINDOW: the last cell was a clock cell
    output wire dec_data_cell,            // the decoder output with the cell that ends in this cycle
    output reg  preamble = 1'b0,          // PREAMBLE_FIELD (U545): in the preamble, as the last word ended
    output wire any_mark,                 // ANY_MARKER_PULSE = ~U615: a mark was found in the last word
    output reg  rd_data = 1'b0,           // RD_DATA (U522): the data bit of the last word
    output wire rg_pin,
    output wire vfoe_seen                 // VFOE: pin 33 low, from the second half of a read word
);
`include "vg93_common.vh"
`ifdef VG93_FD1793_MARKS
    localparam [15:0] BIT13 = 16'h0000;   // FD1793: the A1h / C2h detectors compare every channel bit
`else
    localparam [15:0] BIT13 = 16'h2000;   // channel bit ignored by the A1h / C2h detectors (die defect)
`endif
    localparam [15:0] RAW_A1 = 16'h4489, RAW_C2 = 16'h5224;               // MFM sync bytes, missing clock
    localparam [15:0] RAW_FM_MARK = 16'hABD5, RAW_FM_READ_AM = 16'hABDD;  // FM marks (det_fm_mark, det_read_am)
    localparam [15:0] RAW_TRANS = 16'h2555;                               // A1h -> mark byte junction
    localparam [16:0] RAW_PREAMBLE0 = 17'h0AAAA, RAW_PREAMBLE1 = 17'h15555;

    reg  [16:0] am_window = 17'd0;        // AM16..AM0, AM0 = newest channel bit
    reg  raw_lat0 = 1'b0;                 // U500: transition while RCLK = 0
    reg  raw_lat1 = 1'b0;                 // U511: transition while RCLK = 1
    reg  channel_bit = 1'b0;              // channel bit of the last cell (U574)
    reg  preamble_sample = 1'b0;          // preamble in the window at the last cell end (U544)
    reg  mark_sample = 1'b0;              // a mark in the window at the last cell end (U626)
    reg  dec_sample = 1'b0;               // channel bit one cell earlier (U579)
    reg  dec_data = 1'b0;                 // MFM decoder output at the last cell end (U516)
    reg  mark_flop_n = 1'b0;              // U615: 0 = a mark was found in the last word
    reg  det_a1 = 1'b0, det_fm_mark = 1'b0, det_trans = 1'b0, det_read_am = 1'b0;   // enabled by the last word
                                          // (U566 U567 U1240 U1241)
    reg  rg = 1'b1;                       // RG as the current microword found it (U49); power-on state 1
    reg  vfoe = 1'b0;                     // VFOE as the last word ended

    assign any_mark = !mark_flop_n;

    // ---- mark detectors on the window ----
    wire [15:0] w = am_window[15:0];
    wire am16 = am_window[16];
    wire mark_c2 = (w & ~BIT13) == (RAW_C2 & ~BIT13);
    wire mark_a1 = (w & ~BIT13) == (RAW_A1 & ~BIT13);
    wire sync_mark = (mark_c2 && det_read_am && mfm) || (mark_a1 && det_a1 && mfm) ||
                     (w == RAW_FM_MARK && !am16 && det_fm_mark && !mfm) ||
                     (w == RAW_FM_READ_AM && !am16 && det_read_am && !mfm);
    wire mark = sync_mark || (w == RAW_TRANS && !am16 && det_trans && mfm);
    wire data_cell = !clock_cell;         // CLOCK_WINDOW: the cell that ends is a data cell

    // the cell values a word that ends together with the cell sees (the cell ends first)
    wire preamble_next = am_window == RAW_PREAMBLE0 || am_window == RAW_PREAMBLE1;
    wire dec_data_next = ((dec_sample && !data_cell) || (data_cell && dec_data)) && read_enable;
    wire preamble_cell = cell_ends ? preamble_next : preamble_sample;
    assign dec_data_cell = cell_ends ? dec_data_next : dec_data;

    // ---- bit cell latches: a transition (start of a /RAWREAD pulse) sets the latch of its half cell ----
`ifdef VG93_FAST_SYSCLK
    wire transition0 = 1'b0, transition1 = 1'b0;         // no catcher: the sampled level only
`else
    reg  caught0 = 1'b0, caught1 = 1'b0;                 // flip at every transition of their half cell
    always @(posedge rawread_pin) if (rclk_pin) caught1 <= !caught1; else caught0 <= !caught0;
    reg  [1:0] caught0_q = 2'b00, caught1_q = 2'b00;     // sampled, and the sample before
    always @(posedge sysclk) begin
        caught0_q <= {caught0_q[0], caught0};
        caught1_q <= {caught1_q[0], caught1};
    end
    wire transition0 = caught0_q[0] != caught0_q[1], transition1 = caught1_q[0] != caught1_q[1];
`endif
    wire lat0_now = raw_lat0 || transition0 || (rawread_q && !rclk_q);
    wire lat1_now = raw_lat1 || transition1 || (rawread_q && rclk_q);
    wire cell_bit = rclk_q ? lat0_now : lat1_now;       // the half of the cell that just ended
    wire both_halves = lat0_now && mfm && lat1_now;     // U504: reset both
    wire lat0_clear = cell_ends && (rclk_q || both_halves);   // U499: the latch of the cell that ended
    wire lat1_clear = cell_ends && (both_halves || !rclk_q);

    // ---- U616, mark latch (0 from a mark until the next word): a mark found at the last cell end resets it in the
    // cell window; ~U615 sets it. When the cell ends the window closes and ~U615 may set it again at once ----
    reg  mark_latch_n_held = 1'b0;
    wire mark_latch_n_rs = rs(mark_latch_n_held, mark_sample && cell_window, !mark_flop_n);
    wire mark_latch_n = (cell_ends && !mark_flop_n) ? 1'b1 : mark_latch_n_rs;

    // ---- /VFOE, RG ----
    assign vfoe_seen = second_half ? read_enable : vfoe;
    wire rg_next = set_rg || (!clr_rg && rg);
    wire rg_seen = second_half ? rg_next : rg;
    assign rg_pin = rg_seen && !mr_s;

    always @(posedge sysclk) begin
        // a pulse still low at the cell end sets its latch again at once (the level wins over the reset)
        raw_lat0 <= (lat0_now && !lat0_clear) || (rawread_q && !rclk_q);
        raw_lat1 <= (lat1_now && !lat1_clear) || (rawread_q && rclk_q);
        mark_latch_n_held <= mark_latch_n;

        if (cell_ends) begin
            channel_bit <= cell_bit;
            am_window <= {am_window[15:0], cell_bit};
            preamble_sample <= preamble_next;
            mark_sample <= mark;
            clock_cell <= sync_mark || data_cell;      // the clock window toggles; a sync mark realigns it
            dec_sample <= channel_bit;
            dec_data <= dec_data_next;
        end
        if (word_ends) begin
            preamble <= preamble_cell;
            mark_flop_n <= mark_latch_n;
            rd_data <= dec_data_cell;
            det_a1 <= det_a1_en;
            det_fm_mark <= det_fm_mark_en;
            det_trans <= det_trans_en;
            det_read_am <= det_read_am_en;
            rg <= rg_seen && !mr_next;
            vfoe <= vfoe_seen;
        end
    end
endmodule
