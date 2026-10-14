// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// Command status and the interrupt request (sheets reg_read_logic, int_gen, part of shared_logic).
// The interrupt conditions come from elsewhere: OP (vg93_task_regs), READY / IP edges (vg93_drive), host accesses
// (vg93_host_bus); the vector 002 of an interrupt command is taken in vg93_sequencer.
//
// Flags: SET_BUSY sets BUSY and clears CRC ERROR, RECORD NOT FOUND, WRITE FAULT, WRITE PROTECT; CLR_BUSY ends the
// command; SET_xxx set the flags. The status register shows a word's effect from the word's second half on.
// TYPE1 selects the type I layout of the status register (SET_BUSY sets it, SET_BASE clears it). In the type II /
// III layout bit 5 is WRITE FAULT for a write and RECORD TYPE for a read (SET_WRT_ERR on a deleted data mark).
//
// INTRQ: the RS latch RS_INTRQ is 1 while no interrupt is requested (no_intrq). CLR_BUSY requests one at the end of
// a command (unless the command is D0h..DFh), and so does a D0h..DFh command's condition (index pulse, READY edge,
// immediately) in its interrupt words; both reset the latch in the second half of the word. A host access to the
// status / command register sets it again (clears the request). The pin follows the latch in the first half of a
// word and holds in the second half (REG_INTRQ, errata 5): what happens in the second half reaches the pin when the
// word ends.
module vg93_status (
    input  wire sysclk,
    input  wire word_ends, second_half, second_half_held,
    input  wire mr_s,
    // decoder
    input  wire set_type1, clr_type1,
    input  wire set_busy, clr_busy, set_crc_error, clr_crc_error, set_rnf, set_write_fault, set_write_prot, int_word,
    // interrupt conditions
    input  wire host_int_cmd,             // OP holds D0h..DFh
    input  wire [3:0] int_conditions,     // OP bits 3..0: INT_*
    input  wire ip_edge, ready_rose, ready_fell,
    input  wire bus_cmd,                  // host access to the status / command register
    // status sources
    input  wire ready_seen, tr00_seen, ip_seen, wprt_q, head_loaded, lost_seen, drq,
    output wire type1,                    // TYPE1_CMD
    output wire intrq,                    // INTRQ pin (= ~REG_INTRQ)
    output wire [7:0] status_byte
);
`include "vg93_common.vh"
    localparam INT_READY_RISE = 0, INT_READY_FALL = 1, INT_INDEX = 2, INT_IMMEDIATE = 3;   // bits of int_conditions
    localparam F_BUSY = 0, F_CRC_ERROR = 1, F_RNF = 2, F_WRITE_FAULT = 3, F_WRITE_PROT = 4;  // bits of flags

    // ---- TYPE1: from the new microword and the value of the previous one ----
    reg  type1_d = 1'b0;
    assign type1 = (set_type1 || type1_d) && !clr_type1;

    // ---- interrupt request ----
    wire int_condition = (ip_edge && int_conditions[INT_INDEX]) || (ready_rose && int_conditions[INT_READY_RISE]) ||
                         (ready_fell && int_conditions[INT_READY_FALL]) || int_conditions[INT_IMMEDIATE];
    wire int_request = (int_condition && int_word && host_int_cmd) || (!host_int_cmd && clr_busy);
    reg  no_intrq_held = 1'b0;            // RS_INTRQ register
    reg  no_intrq_pin = 1'b0;             // REG_INTRQ: the pin latch, held in the second half
    wire no_intrq_live = rs(no_intrq_held, int_request && second_half, bus_cmd);   // RS_INTRQ now
    assign intrq = !(second_half_held ? no_intrq_pin : no_intrq_live);

    // ---- flags: next value from the word, shown from the second half of the word, kept at its end ----
    reg  [4:0] flags = 5'd0;              // F_*: as the last word ended
    reg  [4:0] flags_next;
    always @* begin
        flags_next = flags;
        if (set_busy) flags_next = 5'd1 << F_BUSY;      // BUSY, the errors cleared
        if (clr_busy) flags_next[F_BUSY] = 1'b0;
        if (set_crc_error) flags_next[F_CRC_ERROR] = 1'b1;
        if (clr_crc_error) flags_next[F_CRC_ERROR] = 1'b0;
        if (set_rnf) flags_next[F_RNF] = 1'b1;
        if (set_write_fault) flags_next[F_WRITE_FAULT] = 1'b1;
        if (set_write_prot) flags_next[F_WRITE_PROT] = 1'b1;
    end
    wire [4:0] flags_seen = second_half ? flags_next : flags;

    // ---- status register ----
    wire not_ready = mr_s || !ready_seen;
    assign status_byte = type1 ?
        {not_ready, wprt_q, head_loaded, flags_seen[F_RNF], flags_seen[F_CRC_ERROR], tr00_seen, ip_seen,
         flags_seen[F_BUSY]} :
        {not_ready, flags_seen[F_WRITE_PROT], flags_seen[F_WRITE_FAULT], flags_seen[F_RNF], flags_seen[F_CRC_ERROR],
         lost_seen, drq, flags_seen[F_BUSY]};

    always @(posedge sysclk) begin
        no_intrq_held <= no_intrq_live;
        if (!second_half) no_intrq_pin <= no_intrq_live;
        if (word_ends) begin
            type1_d <= type1;
            flags <= flags_seen;
        end
    end
endmodule
