// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// Microword decoder: the only place where the bits of the microword are interpreted. A function of the word only;
// the executing blocks combine these named actions with their state. One table row per microcommand
// (docs/microcode/vg93-microcommands.txt; the program: docs/microcode/vg93-microprogram-v0.2.txt), plus the
// meaning of the hi, mod, rw and imm fields:
//
//   mod 000 / 001  imm presets CNT1 / CNT2 (inverted)
//       01x        long jump (both nibbles, A7 = ~mod[0])
//       100        short jump (low nibble), byte strobe now
//       101 / 111  imm is a control field (101: also EI)
//       110        short jump, EI
//   rw  0xx        write word, rw[1:0] = source of the bit
//       100        read word, RD_DATA into the ID field counter
//       101        read word
//       110        unconditional jump
//       111        nothing
//   hi[0]          in ID_CNT_CALC: also shift CNT1 left (sector length)
//
// "COND true" means: jump if the word has an address, otherwise stay on the word (PC + 0) - every wait loop of
// the microprogram. rw[2] = 1 words count index pulses in CNT1. EI: an interrupt command (D0h..DFh) sends the
// program to vector 002.
module vg93_decoder (
    input  wire [18:0] mword,
    // -> sequencer: the next address
    output wire [7:0] jump_addr,          // inverted address {mod[0], hi, imm}
    output reg  jump_lo, jump_hi,         // PC nibbles a taken jump loads
    output reg  int_vector_en,            // EI
    output reg  jump_always,              // rw = 110
    output reg  [3:0] test_sel,           // TEST_*: the command's jump condition
    output wire [2:0] test_op_bit,        // OP0..OP7: the tested bit of the command register
    output reg  [2:0] stay_sel,           // STAY_*: what a control field word waits for
    output reg  [1:0] skip_sel,           // SKIP_*: when the word skips the next one
    // -> status: command type, status flags, interrupt
    output reg  set_type1, clr_type1,
    output reg  clr_busy, set_crc_error, clr_crc_error, set_rnf, set_write_fault, set_write_prot,
    output reg  int_word,                 // a word in which a D0h..DFh command's condition raises INTRQ
    // -> drive: head load, step, direction, TG43
    output reg  set_hld, clr_hld, step_pulse, set_dirc, clr_dirc, dirc_from_cmp, tg43_from_cmp,
    // -> read path: read gate, mark detectors
    output reg  set_rg, clr_rg, det_a1_en, det_fm_mark_en, det_trans_en, det_read_am_en,
    // -> counters: CNT1, CNT2, ID field counter, byte strobe
    output reg  cnt1_load, cnt2_load,
    output wire [3:0] cnt_preset,         // ~imm
    output reg  cnt1_dec, cnt1_shift_len, cnt2_dec_on_byte, cnt2_dec_on_step,
    output wire cnt1_dec_on_index,        // rw[2] = 1: CNT1 counts index pulses
    output wire id_count,                 // ID_CNT_CALC outside the capture: count the ID field bits down
    output reg  id_capture,               // RD_DATA shifts into the ID field counter
    output reg  byte_sync, byte_sync_on_mark, byte_sync_on_mark_mfm, byte_sync_on_preamble,
    // -> task registers: serial ALU
    output reg  trk_shift, sec_shift,
    output reg  [1:0] trk_fill, sec_fill, // FILL_*
    output reg  ser_inc_force_up, cmp_en,
    output wire [1:0] cmp_operand,        // CMP_*
    // -> data channel: byte words
    output reg  read_byte_word, write_byte_word, format_word, set_lost,
    // -> CRC
    output reg  crc_preset_ffff, crc_preset_a1, crc_preset_fm_trans,
    // -> write path
    output reg  clock_drop,
    output wire [1:0] write_src,          // WR_*
    // shared
    output reg  read_enable,              // a read word (timing: read mode request; read path; CRC input)
    output reg  write_gate,               // a write word (write path; sequencer: write fault vector)
    output reg  set_busy,                 // status; data channel (clears LOST, DRQ; WRITE_READY)
    output reg  ser_inc                   // serial increment words (task registers; counters: byte of 7 words)
);
`include "vg93_ucode.vh"
`include "vg93_actions.vh"

    wire [2:0] mw_hi  = mword[18:16];
    wire [5:0] mw_cmd = mword[15:10];
    wire [2:0] mw_mod = mword[9:7];
    wire [2:0] mw_rw  = mword[6:4];
    wire [3:0] mw_imm = mword[3:0];

    assign jump_addr   = ~{mw_mod[0], mw_hi, mw_imm};
    assign cnt_preset  = ~mw_imm;
    assign test_op_bit = mw_cmd[2:0];
    assign cmp_operand = mw_imm[1:0];
    assign write_src   = mw_rw[1:0];

    // ---- mod: meaning of the hi / imm fields ----
    always @* begin
        {jump_lo, jump_hi, int_vector_en, cnt1_load, cnt2_load, byte_sync} = 0;
        case (mw_mod)
        3'b000: cnt1_load = 1'b1;
        3'b001: cnt2_load = 1'b1;
        3'b010, 3'b011: begin jump_hi = 1'b1; jump_lo = 1'b1; end
        3'b100: begin jump_lo = 1'b1; byte_sync = 1'b1; end
        3'b101: int_vector_en = 1'b1;
        3'b110: begin jump_lo = 1'b1; int_vector_en = 1'b1; end
        default: ;
        endcase
    end

    // ---- imm as a control field (mod = 1x1): "stay while / until" and data path actions ----
    always @* begin
        stay_sel = STAY_NONE;
        {cnt2_dec_on_byte, cnt2_dec_on_step, ser_inc, ser_inc_force_up, cmp_en} = 0;
        if (mw_mod[2] && mw_mod[0])
            case (mw_imm)
            4'b0000: stay_sel = STAY_PREAMBLE;
            4'b0010: stay_sel = STAY_UNTIL_INDEX;
            4'b0011: stay_sel = STAY_CNT1;
            4'b0100, 4'b0101: cmp_en = 1'b1;                           // compare with 0 / 1
            4'b0110, 4'b0111: begin cmp_en = 1'b1; stay_sel = STAY_UNTIL_BYTE; end   // with DATA_SHIFT[7] / RD_DATA
            4'b1000: begin stay_sel = STAY_BYTE_CNT2; cnt2_dec_on_byte = 1'b1; ser_inc = 1'b1; end  // inc / dec by DIRC
            4'b1001: begin stay_sel = STAY_CNT2; cnt2_dec_on_step = 1'b1; end   // step rate delay
            4'b1010: begin stay_sel = STAY_BYTE_CNT2; cnt2_dec_on_byte = 1'b1; end   // CNT2 bytes
            4'b1011, 4'b1101: stay_sel = STAY_CNT2;                    // not used by the ROM
            4'b1100: begin
                stay_sel = STAY_BYTE_CNT2; cnt2_dec_on_byte = 1'b1; ser_inc = 1'b1; ser_inc_force_up = 1'b1;
            end
            4'b1110: stay_sel = STAY_UNTIL_BYTE;
            default: ;                                                 // 0001 (unused), 1111 (empty)
            endcase
    end

    // ---- rw: disk access ----
    always @* begin
        {read_enable, id_capture, jump_always, write_gate} = 0;
        case (mw_rw)
        3'b100: begin read_enable = 1'b1; id_capture = 1'b1; end
        3'b101: read_enable = 1'b1;
        3'b110: jump_always = 1'b1;
        3'b111: ;
        default: write_gate = 1'b1;
        endcase
    end
    assign cnt1_dec_on_index = !write_gate;

    // ---- cmd: one row per microcommand ----
    reg id_calc;
    always @* begin
        test_sel = TEST_NONE;
        skip_sel = SKIP_NONE;
        trk_fill = FILL_ZERO;
        sec_fill = FILL_INC_OUT;
        {set_type1, clr_type1, set_busy, clr_busy, set_crc_error, clr_crc_error, set_rnf, set_write_fault,
         set_write_prot, set_lost, int_word,
         set_hld, clr_hld, step_pulse, set_dirc, clr_dirc, dirc_from_cmp, tg43_from_cmp, set_rg, clr_rg,
         cnt1_dec, cnt1_shift_len, id_calc, trk_shift, sec_shift,
         byte_sync_on_mark, byte_sync_on_mark_mfm, byte_sync_on_preamble,
         read_byte_word, write_byte_word, format_word, det_a1_en, det_fm_mark_en, det_trans_en, det_read_am_en,
         crc_preset_ffff, crc_preset_a1, crc_preset_fm_trans, clock_drop} = 0;
        casez (mw_cmd)
        // SET_BASE: the status register shows the type II / III layout ("base" commands)
        CMD_SET_BASE:        clr_type1 = 1'b1;
        CMD_SET_BUSY:        begin set_busy = 1'b1; set_type1 = 1'b1; end   // also clears the errors, LOST, DRQ
        CMD_CLR_BUSY:        clr_busy = 1'b1;                 // and INTRQ unless D0h..DFh
        // SET_CRC_ERR sets the flag unconditionally and jumps if the CRC is not 0; on success the program clears
        // it again (CLR_CRC_ERR, word 033), so during a good read the host sees CRC ERROR for a few words
        CMD_SET_CRC_ERR:     begin set_crc_error = 1'b1; test_sel = TEST_CRC_NONZERO; end
        CMD_CLR_CRC_ERR:     clr_crc_error = 1'b1;
        CMD_SET_REC_NOT_FND: set_rnf = 1'b1;
        CMD_SET_WRT_ERR:     set_write_fault = 1'b1;          // status bit 5: WRITE FAULT, RECORD TYPE when reading
        CMD_SET_WRT_PRT:     set_write_prot = 1'b1;
        CMD_SET_LOST:        set_lost = 1'b1;
        CMD_SET_RG:          set_rg = 1'b1;
        CMD_CLR_RG:          clr_rg = 1'b1;
        CMD_SET_HLD:         set_hld = 1'b1;
        CMD_CLR_HLD:         clr_hld = 1'b1;
        // the two words of the wait loop between commands (003 / 004): a command written by the host skips the
        // next word and leaves the loop
        CMD_CLR_HLD_INT:     begin clr_hld = 1'b1; int_word = 1'b1; skip_sel = SKIP_NEW_CMD; end
        CMD_CNT1_TST_INT:    begin test_sel = TEST_CNT1_RUNNING; int_word = 1'b1; skip_sel = SKIP_NEW_CMD; end
        CMD_HLD_HLT_TST:     test_sel = TEST_HEAD_NOT_LOADED;
        CMD_STEP:            step_pulse = 1'b1;
        CMD_UPD_TG43:        tg43_from_cmp = 1'b1;
        CMD_CLR_DIRC:        clr_dirc = 1'b1;
        CMD_UPD_DIRC:        dirc_from_cmp = 1'b1;
        CMD_SET_DIRC:        set_dirc = 1'b1;
        CMD_GOTO:            test_sel = TEST_ALWAYS;
        CMD_READY_TST:       test_sel = TEST_NOT_READY;
        CMD_TR0_TST:         test_sel = TEST_TR00_OFF_OR_IN;
        CMD_DDEN_TST:        test_sel = TEST_FM;
        6'b100???:           test_sel = TEST_OP_BIT_CLEAR;    // CMD_OP0 .. CMD_OP7
        CMD_ID_CNT_CALC:     begin test_sel = TEST_ID_NONZERO; id_calc = 1'b1; cnt1_shift_len = mw_hi[0]; end
        CMD_CMP_MATCH:       test_sel = TEST_CMP_DIFFER;
        CMD_TRK_ROL:         begin trk_shift = 1'b1; trk_fill = FILL_INC_OUT; end
        CMD_TRK_SH0:         begin trk_shift = 1'b1; trk_fill = FILL_ZERO; end
        CMD_TRK_SH1:         begin trk_shift = 1'b1; trk_fill = FILL_ONE; end
        CMD_SEC_ROL:         begin sec_shift = 1'b1; sec_fill = FILL_INC_OUT; end
        CMD_CNT1_TST:        test_sel = TEST_CNT1_RUNNING;
        CMD_CNT1_TST_DEC:    begin test_sel = TEST_CNT1_RUNNING; cnt1_dec = 1'b1; end
        CMD_CNT1_DEC:        cnt1_dec = 1'b1;
        CMD_CRC_CLR:         crc_preset_ffff = 1'b1;
        CMD_WPRT_TST:        test_sel = TEST_NOT_WPRT;
        CMD_WR_DRQ_TST:      test_sel = TEST_WRITE_DRQ_OFF;
        CMD_WRITE:           write_byte_word = 1'b1;
        CMD_WRITE_STB_TST:   begin write_byte_word = 1'b1; test_sel = TEST_BYTE_STB; end
        CMD_FORMAT:          begin write_byte_word = 1'b1; format_word = 1'b1; end
        CMD_READ:            read_byte_word = 1'b1;
        CMD_SEC_READ:        begin read_byte_word = 1'b1; sec_shift = 1'b1; sec_fill = FILL_RD_DATA; end
        // READ_AM: the marks READ TRACK synchronises on (MFM A1h / C2h, FM marks)
        CMD_READ_AM:         begin
            read_byte_word = 1'b1; det_a1_en = 1'b1; det_fm_mark_en = 1'b1; det_read_am_en = 1'b1;
            byte_sync_on_mark_mfm = 1'b1;
        end
        CMD_RDATA_TST:       test_sel = TEST_RD_ZERO;
        CMD_CLK_DROP:        clock_drop = 1'b1;
        CMD_TRANS_AM:        begin det_fm_mark_en = 1'b1; det_trans_en = 1'b1; crc_preset_fm_trans = 1'b1; end
        CMD_A1_DET:          det_a1_en = 1'b1;
        CMD_A1_DET_CRC:      begin det_a1_en = 1'b1; crc_preset_a1 = 1'b1; byte_sync_on_mark = 1'b1; end
        CMD_PREAM_STB_TST:   skip_sel = SKIP_PREAMBLE_BYTE;
        CMD_PREAM_INI_TST:   begin skip_sel = SKIP_PREAMBLE; byte_sync_on_preamble = 1'b1; end
        default: ;                                            // NOP 3Fh and the unused codes
        endcase
    end
    assign id_count = id_calc && !id_capture;
endmodule
