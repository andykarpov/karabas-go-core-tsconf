// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// The drive side (sheets misc_logic, tr43, step_prescaler, shared_logic, parts of int_gen and reg_read_logic):
// drive status inputs, head positioning (step rate, STEP, DIRC, TG43) and head load (HLD with HLT).
// Elsewhere: the step delay counts CNT2 by step_tick (vg93_counters), the comparator that sets DIRC / TG43 is in
// vg93_task_regs, the TR00 / READY tests in vg93_sequencer, the interrupt on READY edges in vg93_status.
//
// Inputs READY, TR00, IP: in the second half of a word the chip's input latches are open (the status shows the pin
// itself, a READY edge can raise an interrupt): ready_seen = second_half ? pin : ready. HLT is sampled as a word
// ends.
// Step rate: a counter 0..249 ticks once per 250 microwords; in MFM (words twice as short) only every second tick
// counts, so the rate does not depend on the density. /TEST low ticks in every word. (On the chip an 8-bit LFSR
// that runs from 9Fh to 0 in 250 steps; docs/behav_map.md.)
// HLD: SET_HLD / CLR_HLD words change the pin from the word's second half on; the microprogram's own view
// (HLD_HLT_TST, status bit 5) changes when the word ends. /MR holds HLD low.
module vg93_drive (
    input  wire sysclk,
    input  wire word_ends, second_half,
    input  wire mr_s, mr_next, mfm,
    // pins, sampled, active high
    input  wire ready_q, tr00_q, ip_q, hlt_q, test_q,
    // decoder
    input  wire step_pulse, set_dirc, clr_dirc, dirc_from_cmp, tg43_from_cmp, set_hld, clr_hld,
    input  wire cmp_greater,
    output reg  ready = 1'b0,             // READY as the last word ended (U669 = U1027)
    output reg  tr00 = 1'b0,              // TR00 as the last word ended (U699)
    output wire ready_seen, tr00_seen, ip_seen,   // the latches as the status shows them (READY_S, TR00_S, IP)
    output wire ready_rose, ready_fell,   // READY edges seen by the interrupt logic (second half only)
    output wire ip_edge,                  // an index pulse began
    output wire step_tick,                // step rate tick (STEP_STB)
    output reg  step_out = 1'b0,          // STEP pin
    output reg  dirc = 1'b0,              // DIRC pin: 1 = step in
    output wire tg43,                     // TG43 pin, from the second half of the word
    output wire hld_pin,
    output wire head_loaded               // HLD & HLT: status bit 5, HLD_HLT_TST
);
    localparam [7:0] STEP_PERIOD = 8'd250;    // microwords per step rate tick

    reg  ip = 1'b0;                       // IP as the last word ended (U702, status bit 1)
    reg  ip_sample = 1'b0;                // U1015, U1016: /IP sampled at the word ends
    reg  ip_sample_d = 1'b0;
    reg  hlt = 1'b0;                      // HLT as the last word ended (U639)
    reg  [7:0] step_count = STEP_PERIOD - 8'd1;   // 0..249, a tick at 249 (power-on: 249)
    reg  step_tick_skip = 1'b0;           // MFM: this period's tick is dropped (U1266)
    reg  tg43_off = 1'b0;                 // ~TG43 as the last word ended (U585)
    reg  hld = 1'b1;                      // HLD as the current microword found it (U55); power-on state 1

    // ---- drive status inputs ----
    assign ready_seen = second_half ? ready_q : ready;
    assign tr00_seen = second_half ? tr00_q : tr00;
    assign ip_seen = second_half ? ip_q : ip;
    assign ready_rose = ready_seen && !ready;
    assign ready_fell = !ready_seen && ready;
    assign ip_edge = ip_sample && !ip_sample_d;

    // ---- step rate ----
    wire period_end = step_count == STEP_PERIOD - 8'd1;
    assign step_tick = (!mfm && period_end) || test_q || (period_end && !step_tick_skip);

    // ---- TG43 ----
    wire tg43_off_next = tg43_from_cmp ? cmp_greater : tg43_off;
    wire tg43_off_seen = second_half ? tg43_off_next : tg43_off;
    assign tg43 = !tg43_off_seen;

    // ---- head load ----
    wire hld_next = set_hld || (!clr_hld && hld);
    wire hld_seen = second_half ? hld_next : hld;
    assign hld_pin = hld_seen && !mr_s;
    assign head_loaded = hld && hlt;

    always @(posedge sysclk) begin
        if (word_ends) begin
            ready <= ready_seen;
            tr00 <= tr00_seen;
            ip <= ip_seen;
            ip_sample <= ip_q;
            ip_sample_d <= ip_sample;
            hlt <= hlt_q;
            tg43_off <= tg43_off_seen;
            step_count <= (period_end || mr_s) ? 8'd0 : step_count + 8'd1;   // /MR restarts the period
            step_tick_skip <= (step_tick_skip != period_end) || !mfm;
            step_out <= step_pulse;
            if (dirc_from_cmp) dirc <= cmp_greater;
            else if (set_dirc) dirc <= 1'b1;
            else if (clr_dirc) dirc <= 1'b0;
            hld <= hld_seen && !mr_next;
        end
    end
endmodule
