// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// Microword fields and microcommand codes: included by vg93_decoder only, the one place where the microword is
// interpreted (tools/check_behav_style.py checks it). The encodings of the decoder outputs are in vg93_actions.vh.
// The microprogram itself, readable: docs/microcode/vg93-microprogram-v0.2.txt; microcommands:
// docs/microcode/vg93-microcommands.txt.
//
//   bit  18..16  15..10  9..7  6..4  3..0
//         hi      cmd    mod    rw    imm
// hi and imm also form the inverted jump address {mod[0], hi, imm}; imm is the inverted counter preset.

localparam [5:0]
    CMD_SET_LOST        = 6'h00,
    CMD_READY_TST       = 6'h01,
    CMD_TR0_TST         = 6'h02,
    CMD_CLK_DROP        = 6'h03,
    CMD_TRK_ROL         = 6'h04,
    CMD_TRK_SH0         = 6'h06,
    CMD_TRK_SH1         = 6'h07,
    CMD_HLD_HLT_TST     = 6'h08,
    CMD_SET_BASE        = 6'h0A,
    CMD_SET_HLD         = 6'h0B,
    CMD_CLR_HLD_INT     = 6'h0C,
    CMD_CNT1_TST_INT    = 6'h0D,
    CMD_CLR_HLD         = 6'h0E,
    CMD_RDATA_TST       = 6'h0F,
    CMD_READ            = 6'h11,
    CMD_SEC_READ        = 6'h12,
    CMD_READ_AM         = 6'h13,
    CMD_DDEN_TST        = 6'h14,
    CMD_UPD_TG43        = 6'h15,
    CMD_STEP            = 6'h16,
    CMD_TRANS_AM        = 6'h17,
    CMD_A1_DET_CRC      = 6'h18,
    CMD_WR_DRQ_TST      = 6'h19,
    CMD_GOTO            = 6'h1A,
    CMD_PREAM_STB_TST   = 6'h1B,
    CMD_WPRT_TST        = 6'h1C,
    CMD_PREAM_INI_TST   = 6'h1D,
    CMD_CLR_RG          = 6'h1E,
    CMD_SET_RG          = 6'h1F,
    CMD_OP0             = 6'h20,  // CMD_OP0 .. CMD_OP7 = 20h .. 27h: test bit n of the command register
    CMD_SET_BUSY        = 6'h28,
    CMD_ID_CNT_CALC     = 6'h2A,
    CMD_SET_CRC_ERR     = 6'h2B,
    CMD_SET_REC_NOT_FND = 6'h2C,
    CMD_SET_WRT_ERR     = 6'h2D,
    CMD_SET_WRT_PRT     = 6'h2E,
    CMD_A1_DET          = 6'h2F,
    CMD_CLR_BUSY        = 6'h30,
    CMD_CRC_CLR         = 6'h31,
    CMD_SEC_ROL         = 6'h32,
    CMD_CLR_CRC_ERR     = 6'h33,
    CMD_CLR_DIRC        = 6'h34,
    CMD_UPD_DIRC        = 6'h35,
    CMD_SET_DIRC        = 6'h36,
    CMD_CMP_MATCH       = 6'h37,
    CMD_WRITE_STB_TST   = 6'h38,
    CMD_WRITE           = 6'h3A,
    CMD_FORMAT          = 6'h3B,
    CMD_CNT1_TST_DEC    = 6'h3C,
    CMD_CNT1_TST        = 6'h3D,
    CMD_CNT1_DEC        = 6'h3E;
