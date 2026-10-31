// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// CRC-16 CCITT (x^16 + x^12 + x^5 + 1), one bit per microword (sheet crc16_ccitt).
//
// The input bit is the data bit read from the disk (read words) or the bit being written. Presets stand for the
// bytes before the protected field that are not shifted through the generator:
//   FFFFh  CRC_CLR, and the FM mark bytes F8h..FBh / FEh written by FORMAT;
//   968Bh  = CRC of A1h A1h A1h: A1_DET_CRC, and the A1h written by FORMAT (F5h in the data);
//   FFE0h  TRANS_AM in FM: the transition mark found, the mark byte is shifted in afterwards.
// Presets that coincide combine as a wired AND of their values.
module vg93_crc (
    input  wire sysclk,
    input  wire word_ends,
    input  wire mfm,
    // decoder
    input  wire crc_preset_ffff, crc_preset_a1, crc_preset_fm_trans, read_enable,
    input  wire rd_data,                  // bit read from the disk
    input  wire write_bit,                // bit being written
    input  wire load_a1,                  // FORMAT writes A1h
    input  wire format_fm_mark,           // FORMAT writes an FM mark byte
    output wire crc_msb,                  // CRC[15]: the bit a CRC write word writes
    output wire crc_nonzero
);
    localparam [15:0] CRC_POLY = 16'h1021, CRC_PRESET_A1A1A1 = 16'h968B, CRC_PRESET_FM_TRANS = 16'hFFE0;

    reg  [15:0] crc = 16'd0;
    assign crc_msb = crc[15];
    assign crc_nonzero = crc != 16'd0;

    wire preset_fm = crc_preset_fm_trans && !mfm;
    wire preset_a1 = load_a1 || crc_preset_a1;
    wire preset = preset_fm || format_fm_mark || crc_preset_ffff || preset_a1;
    wire [15:0] preset_value = (preset_fm ? CRC_PRESET_FM_TRANS : 16'hFFFF) &
                               (preset_a1 ? CRC_PRESET_A1A1A1 : 16'hFFFF);
    wire in_bit = read_enable ? rd_data : write_bit;
    wire feedback = in_bit != crc[15];

    always @(posedge sysclk)
        if (word_ends)
            crc <= preset ? preset_value : {crc[14:0], 1'b0} ^ (feedback ? CRC_POLY : 16'h0000);
endmodule
