// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// Counters of the microprogram (sheets counter1, counter2, id_fld_cnt, byte_strobe_gen).
//
//   CNT1  8-bit: preset from the word (inverted imm), counts down in CNT1_DEC / CNT1_TST_DEC words and on index
//         pulses in words with rw[2] = 1 (revolutions), shifts left in ID_CNT_CALC with hi[0] (sector length:
//         CNT1 = 4 << (n + 1) blocks of 16 bytes).
//   CNT2  4-bit: preset from the word, counts down on byte strobes or step-rate ticks.
//   ID field counter: the two low bits of an ID field byte pass through it while reading (side byte: the side
//         check; length byte: the sector size), then ID_CNT_CALC counts them down.
//   Byte strobe (BYTE_STB): marks the last bit of a byte. The bit counter counts the microwords of a byte, 0..7, and
//         the strobe comes with bit 7. The strobe restarts the count; it is also forced by a sync mark, a preamble
//         byte, mod = 100 words and the first word of a serial increment run. In the increment words the count
//         skips bit 4, so a byte there takes 7 words (on the chip a 4-stage shift counter, U653 U646 U651 U652,
//         whose increment input does this).
module vg93_counters (
    input  wire sysclk,
    input  wire word_ends,
    // decoder
    input  wire cnt1_load, cnt2_load,
    input  wire [3:0] cnt_preset,
    input  wire cnt1_dec, cnt1_dec_on_index, cnt1_shift_len, cnt2_dec_on_byte, cnt2_dec_on_step,
    input  wire id_capture, id_count,
    input  wire byte_sync, byte_sync_on_mark, byte_sync_on_mark_mfm, byte_sync_on_preamble, ser_inc,
    // events counted
    input  wire ip_edge, step_tick, rd_data,
    input  wire mfm, any_mark, preamble,  // byte strobe sync: a mark found, the preamble
    output wire cnt1_zero, cnt2_zero, id_nonzero,
    output wire byte_stb,
    output wire ser_inc_sync              // first word of a serial increment run (task registers: carry)
);
    wire [7:0] cnt1;
    wire [3:0] cnt2;
    reg  id_bit0 = 1'b0;                  // U41
    reg  id_bit1 = 1'b0;                  // U42
    reg  [2:0] bit_count = 3'd4;          // microword of the byte, 0..7 (power-on: 4)
    reg  inc_run = 1'b0;                  // the last word was a serial increment word (U632)

    // CNT1, CNT2: vg93_dcnt down counters (load, CNT1 also shifts; a carry chain counter in rtl_epm570)
    wire cnt1_step = cnt1_load || cnt1_shift_len || cnt1_dec || (cnt1_dec_on_index && ip_edge);
    wire cnt2_step = cnt2_load || (cnt2_dec_on_step && !cnt2_zero && step_tick) || (cnt2_dec_on_byte && byte_stb);
    vg93_dcnt #(8) cnt1_counter (.clk(sysclk), .ena(word_ends && cnt1_step), .sload(cnt1_load),
        .shift(cnt1_shift_len), .d({4'd0, cnt_preset}), .q(cnt1), .zero(cnt1_zero));
    vg93_dcnt #(4) cnt2_counter (.clk(sysclk), .ena(word_ends && cnt2_step), .sload(cnt2_load), .shift(1'b0),
        .d(cnt_preset), .q(cnt2), .zero(cnt2_zero));
    assign id_nonzero = id_bit0 || id_bit1;

    // ---- byte strobe ----
    assign ser_inc_sync = !inc_run && ser_inc;
    wire byte_sync_now = byte_sync || (byte_sync_on_mark && any_mark) || (byte_sync_on_mark_mfm && any_mark && mfm) ||
                         (byte_sync_on_preamble && preamble);
    assign byte_stb = ser_inc_sync || byte_sync_now || bit_count == 3'd7;

    always @(posedge sysclk)
        if (word_ends) begin
            if (id_capture) begin                     // the ID field bits pass through while reading
                id_bit0 <= rd_data;
                id_bit1 <= id_bit0;
            end else if (id_count) begin              // count down
                id_bit0 <= !id_bit0;
                if (!id_bit0) id_bit1 <= !id_bit1;
            end

            inc_run <= ser_inc;
            bit_count <= byte_stb ? 3'd0 : (ser_inc && bit_count == 3'd3) ? 3'd5 : bit_count + 3'd1;
        end
endmodule
