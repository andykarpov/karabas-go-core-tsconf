// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// Encodings of the decoder outputs that are more than a flag. The blocks include this file; the microword itself
// (fields, CMD_* codes: vg93_ucode.vh) is interpreted in vg93_decoder only.

// test_sel: the command's jump condition (sequencer)
localparam [3:0]
    TEST_NONE            = 4'd0,
    TEST_ALWAYS          = 4'd1,   // GOTO
    TEST_NOT_READY       = 4'd2,   // READY_TST
    TEST_TR00_OFF_OR_IN  = 4'd3,   // TR0_TST: not on track 0, or stepping in
    TEST_FM              = 4'd4,   // DDEN_TST
    TEST_NOT_WPRT        = 4'd5,   // WPRT_TST
    TEST_HEAD_NOT_LOADED = 4'd6,   // HLD_HLT_TST
    TEST_RD_ZERO         = 4'd7,   // RDATA_TST
    TEST_WRITE_DRQ_OFF   = 4'd8,   // WR_DRQ_TST
    TEST_ID_NONZERO      = 4'd9,   // ID_CNT_CALC
    TEST_BYTE_STB        = 4'd10,  // WRITE_STB_TST
    TEST_CMP_DIFFER      = 4'd11,  // CMP_MATCH
    TEST_CRC_NONZERO     = 4'd12,  // SET_CRC_ERR
    TEST_CNT1_RUNNING    = 4'd13,  // CNT1_TST, CNT1_TST_DEC, CNT1_TST_INT
    TEST_OP_BIT_CLEAR    = 4'd14;  // OP0 .. OP7

// stay_sel: what a word with a control field (mod = 1x1) waits for - it stays on itself (PC + 0) while ...
localparam [2:0]
    STAY_NONE           = 3'd0,
    STAY_PREAMBLE       = 3'd1,    // ... the preamble lasts
    STAY_UNTIL_INDEX    = 3'd2,    // ... until an index pulse begins
    STAY_CNT1           = 3'd3,    // ... CNT1 runs
    STAY_UNTIL_BYTE     = 3'd4,    // ... until the byte strobe
    STAY_CNT2           = 3'd5,    // ... CNT2 runs
    STAY_BYTE_CNT2      = 3'd6;    // ... until the byte strobe, or while CNT2 runs (byte counting words)

// skip_sel: when a word skips the next one (PC + 2); a mark found (any_mark) and FORMAT F7h skip in any word
localparam [1:0]
    SKIP_NONE           = 2'd0,
    SKIP_NEW_CMD        = 2'd1,    // the host wrote a command: leave the wait loop
    SKIP_PREAMBLE_BYTE  = 2'd2,    // a preamble byte ended
    SKIP_PREAMBLE       = 2'd3;    // in the preamble

// trk_fill / sec_fill: the bit shifted in at the bottom of TRK / SEC
localparam [1:0] FILL_ZERO = 2'd0, FILL_ONE = 2'd1, FILL_INC_OUT = 2'd2, FILL_RD_DATA = 2'd3;
// cmp_operand: second operand bit of the serial comparator
localparam [1:0] CMP_ZERO = 2'd0, CMP_ONE = 2'd1, CMP_SHIFT_MSB = 2'd2, CMP_RD_DATA = 2'd3;
// write_src: the bit a write word writes
localparam [1:0] WR_CRC = 2'd0, WR_SHIFT = 2'd1, WR_ZERO = 2'd2, WR_ONE = 2'd3;
