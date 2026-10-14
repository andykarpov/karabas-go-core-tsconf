// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// Microprogram sequencer (sheets instruction_logic, shared_logic): microcode ROM, program counter, the jump
// condition and the skip. The ROM image is docs/microcode/vg93-microcode-rom.hex (the simulation scripts copy it
// next to the model, Quartus reads it from the project directory); the readable program with the word addresses
// used below: docs/microcode/vg93-microprogram-v0.2.txt.
//
// Life of a command: after /MR the program starts at 000; a finished command clears BUSY at 002 (CLR_BUSY, INTRQ)
// and waits in 003 / 004. A command written by the host (wr_cmd_en) makes the wait word skip into 005 / 006,
// which go to 000: SET_BUSY, then a dispatch on the bits of the command register (OP7.., word 007 on) runs the
// command's part of the program, which returns to 002.
//
// The next address is
//   - a vector under /MR, on a write fault in a write word (001) and when the command register holds an interrupt
//     command D0h..DFh in an "EI" word (002). The vectors set address bits: /MR gives 000, but /MR with a write
//     fault gives 001 and both vectors 003, as on the chip (the address bits are ORed);
//   - otherwise PC + 0 (condition true and no address in the word: wait on the word), PC + 1, PC + 2 (skip), and on a
//     taken jump the low and / or high nibble of the word's address.
// The skip is the second way to branch: a wait word that sees its event goes on at PC + 2 instead of PC + 1:
//   any_mark       a mark found (A1_DET, TRANS_AM, READ_AM wait words), e.g. 139 -> 141;
//   SKIP_NEW_CMD   leave the wait loop between commands;
//   SKIP_PREAMBLE*  count the preamble bytes;
//   format_f7      FORMAT writes the two CRC bytes for F7h: the next word is skipped.
// The +0 / +1 / +2 choice follows the word's first half and holds in its second half (U65 latch); the jump load
// stays live until the word ends.
module vg93_sequencer (
    input  wire sysclk,
    input  wire word_ends, power_on, second_half, second_half_held,
    // decoder
    input  wire [7:0] jump_addr,
    input  wire jump_lo, jump_hi, int_vector_en, jump_always, write_gate,
    input  wire [3:0] test_sel,
    input  wire [2:0] test_op_bit,
    input  wire [2:0] stay_sel,
    input  wire [1:0] skip_sel,
    // what the tests look at
    input  wire [7:0] cmd_reg,
    input  wire host_int_cmd,             // the command register holds D0h..DFh
    input  wire mr_s, mfm,
    input  wire pin33_low,                // pin 33 low: external /WF, or the own /VFOE (vg93_top)
    input  wire ready, tr00, dirc, wprt_q, head_loaded,
    input  wire rd_data, write_drq_off, id_nonzero, byte_stb, cmp_differ, crc_nonzero,
    input  wire cnt1_zero, cnt2_zero, preamble, ip_edge, any_mark,
    input  wire format_f7, wr_cmd_en,
    output reg  [7:0] pc = 8'd0,          // address of the current microword
    output reg  [18:0] mword = 19'd0      // the current microword (REG_MCMD)
);
`include "vg93_actions.vh"

`ifndef VG93_ROM_FILE
`define VG93_ROM_FILE "vg93-microcode-rom.hex"
`endif
    reg [18:0] rom [0:255];
    initial $readmemh(`VG93_ROM_FILE, rom);

    reg  wf_s = 1'b0;                     // U1083: pin 33 low as the last word ended (write fault vector)

    // ---- jump condition (COND_PC) ----
    reg test;
    always @* begin
        case (test_sel)
        TEST_ALWAYS:          test = 1'b1;
        TEST_NOT_READY:       test = !ready;
        TEST_TR00_OFF_OR_IN:  test = !tr00 || dirc;
        TEST_FM:              test = !mfm;
        TEST_NOT_WPRT:        test = !wprt_q;
        TEST_HEAD_NOT_LOADED: test = !head_loaded;
        TEST_RD_ZERO:         test = !rd_data;
        TEST_WRITE_DRQ_OFF:   test = write_drq_off;
        TEST_ID_NONZERO:      test = id_nonzero;
        TEST_BYTE_STB:        test = byte_stb;
        TEST_CMP_DIFFER:      test = cmp_differ;
        TEST_CRC_NONZERO:     test = crc_nonzero;
        TEST_CNT1_RUNNING:    test = !cnt1_zero;
        TEST_OP_BIT_CLEAR:    test = !cmd_reg[test_op_bit];
        default:              test = 1'b0;
        endcase
    end
    reg stay;
    always @* begin
        case (stay_sel)
        STAY_PREAMBLE:    stay = preamble;
        STAY_UNTIL_INDEX: stay = !ip_edge;
        STAY_CNT1:        stay = !cnt1_zero;
        STAY_UNTIL_BYTE:  stay = !byte_stb;
        STAY_CNT2:        stay = !cnt2_zero;
        STAY_BYTE_CNT2:   stay = !byte_stb || !cnt2_zero;
        default:          stay = 1'b0;
        endcase
    end
    wire cond = test || jump_always || stay;

    // ---- skip the next word ----
    reg skip_word;
    always @* begin
        case (skip_sel)
        SKIP_NEW_CMD:       skip_word = wr_cmd_en;
        SKIP_PREAMBLE_BYTE: skip_word = preamble && byte_stb;
        SKIP_PREAMBLE:      skip_word = preamble;
        default:            skip_word = 1'b0;
        endcase
    end
    wire skip = skip_word || format_f7 || any_mark;

    // ---- next address ----
    reg  [7:0] pc_seq_held = 8'd0;        // U65: PC + 0 / 1 / 2, holds in the second half of the word
    wire vec_write_fault = wf_s && write_gate;
    wire vec_int_cmd = int_vector_en && host_int_cmd;
    wire jump = cond && !skip;
    wire [7:0] pc_seq = pc + (skip ? 8'd2 : cond ? 8'd0 : 8'd1);
    wire [7:0] pc_seq_used = second_half_held ? pc_seq_held : pc_seq;
    wire [7:0] pc_next = (mr_s || vec_write_fault || vec_int_cmd) ? {6'd0, vec_int_cmd, vec_write_fault} :
                         {(jump && jump_hi) ? jump_addr[7:4] : pc_seq_used[7:4],
                          (jump && jump_lo) ? jump_addr[3:0] : pc_seq_used[3:0]};
    wire [7:0] rom_addr = power_on ? pc : pc_next;   // the power-on edge reloads the word at PC

    always @(posedge sysclk) begin
        if (!second_half) pc_seq_held <= pc_seq;
        if (word_ends) begin
            pc <= rom_addr;
            mword <= rom[rom_addr];        // block RAM, read with the address of the coming word
            wf_s <= pin33_low;
        end
    end
endmodule
