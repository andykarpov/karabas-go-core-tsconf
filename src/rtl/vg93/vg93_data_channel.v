// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// The byte channel between the host and the disk (sheets data_reg, sig_driver_logic, the FORMAT part of
// data_writer): data register DATA, shift register DATA_SHIFT, the handshake DRQ / LOST, the special bytes of
// FORMAT.
//
// Reading: in read mode one microword is one data bit of the disk; the bits from the MFM decoder shift into
// DATA_SHIFT one per microword; at the byte strobe of a read word the byte goes to DATA and DRQ rises; the host
// reading DATA clears DRQ. A byte strobe that finds the previous byte not taken (READ_PEND) sets LOST.
// Writing: at the byte strobe of a write word DATA goes to DATA_SHIFT, whose top bit the write path writes, and DRQ
// asks for the next byte; WRITE_READY tells whether the host supplied it, LOST when it did not.
//
// FORMAT (WRITE TRACK) writes the byte in DATA, except: F5h -> A1h with a missing clock (MFM sync, CRC preset),
// F6h -> C2h with a missing clock, F7h -> two CRC bytes (the next word is skipped), FCh -> index mark (missing
// clocks D7h, FM), F8h..FBh / FEh in FM -> mark with clock C7h and CRC preset FFFFh.
//
// DRQ, READ_PEND are RS latches on the die: set and reset by the host bus and by terms that act only in the second
// half of the word. Each is a register (*_held) plus its current value (*_live) from the same terms.
module vg93_data_channel (
    input  wire sysclk,
    input  wire word_ends, second_half,
    // decoder
    input  wire read_byte_word, write_byte_word, format_word, set_busy, set_lost,
    // state of other blocks
    input  wire byte_stb,                 // byte strobe (counters)
    input  wire type1, mfm,
    input  wire cnt1_zero, cnt2_zero,
    input  wire dec_data_cell,            // MFM decoder output with this cycle's cell: the next bit into DATA_SHIFT
    // host bus
    input  wire [7:0] dal_in,
    input  wire wr_data_en,               // host write of DATA in this microword
    input  wire bus_data, bus_data_read,  // host access to DATA (read or write), read of DATA
    output wire [7:0] data_seen,          // DATA as the host reads it (being formed in the second half)
    output wire shift_msb,                // DATA_SHIFT[7]: the bit a write word writes, comparator operand
    output reg  drq = 1'b0,               // REG_DIRQ (schematic name): DRQ pin
    output reg  write_ready = 1'b0,       // DATA holds a byte for the write path
    output wire lost_seen,                // LOST (status bit 2), from the second half of the word
    output wire write_drq_off,            // no DRQ for a write: counters done, or no byte supplied
    // FORMAT special bytes
    output wire format_f7,                // F7h: write the CRC, skip the next word (sequencer)
    output wire format_fm_mark,           // FM mark byte: CRC preset FFFFh, missing clocks (CRC, write path)
    output wire index_mark,               // FCh: index mark, missing clocks (write path)
    output wire load_a1,                  // F5h: A1h into DATA_SHIFT, CRC preset 968Bh (CRC, write path)
    output wire load_c2                   // F6h: C2h into DATA_SHIFT (write path)
);
`include "vg93_common.vh"
    localparam [7:0] FMT_A1 = 8'hF5, FMT_C2 = 8'hF6, FMT_CRC = 8'hF7, FMT_INDEX = 8'hFC, FMT_FM_MARK_FE = 8'hFE;
    localparam [7:0] MARK_A1 = 8'hA1, MARK_C2 = 8'hC2;

    reg  [7:0] data = 8'd0;               // DATA: the byte the microword works on
    reg  [7:0] data_shift = 8'd0;
    reg  read_pend = 1'b0;                // REG_READ_PEND: a read byte not yet taken as the last word ended
    reg  lost = 1'b0;                     // LOST as the last word ended (U484)

    wire byte_read_stb = read_byte_word && byte_stb;
    wire byte_write_stb = write_byte_word && byte_stb;
    assign shift_msb = data_shift[7];

    // ---- FORMAT ----
    wire format_stb = format_word && byte_stb && write_ready;
    assign index_mark = data == FMT_INDEX && format_stb;
    assign format_fm_mark = (data == FMT_FM_MARK_FE || data[7:2] == 6'b111110) && format_stb && !mfm;   // FEh, F8h..FBh
    assign load_c2 = data == FMT_C2 && format_stb;
    assign format_f7 = data == FMT_CRC && format_stb;
    assign load_a1 = data_seen == FMT_A1 && format_stb;     // checked on the byte just being loaded

    // ---- DATA ----
    wire [7:0] data_next = wired_and(data, wr_data_en, dal_in, byte_read_stb, data_shift);
    assign data_seen = second_half ? data_next : data;

    // ---- LOST: a byte strobe that finds the byte not taken / not supplied ----
    wire lost_next = set_lost || (byte_write_stb && !write_ready && !type1) ||
                     (!type1 && byte_read_stb && read_pend) || (!set_busy && lost);
    assign lost_seen = second_half ? lost_next : lost;

    // ---- DRQ handshake: DRQ rises in the second half of a byte strobe word if the last read byte was taken; a host
    // read of DATA clears DRQ and releases READ_PEND ----
    assign write_drq_off = (cnt1_zero && cnt2_zero) || !write_ready;
    reg  drq_held = 1'b0, read_pend_held = 1'b0;
    wire drq_reset = (set_busy && second_half) || bus_data;
    wire drq_by_write = !write_drq_off && byte_write_stb && !type1 && second_half;
    wire drq_by_read = byte_read_stb && !type1 && second_half;   // unless a read byte is pending
    wire pend_release = !bus_data_read && second_half;           // READ_PEND follows DRQ in the second half ...
    // The two latches settled (src/vg93.c async_latches: DRQ is set unless a read byte is pending, READ_PEND follows
    // DRQ and is released when DRQ falls, not during a read of DATA; a host read that cleared DRQ releases READ_PEND,
    // after which the byte strobe sets DRQ again), written as the fixed point of the passes: R = S = 1 keeps the
    // value (no priority). Checked exhaustively against three passes of the RS form (given that the set and release
    // terms act in the second half only).
    wire drq_live, read_pend_live;                               // RS_DRQ, RS_READ_PEND
    assign drq_live = (drq_by_write && drq_held) ||
                      (!drq_reset && (drq_by_write || drq_held || (drq_by_read && (pend_release || !read_pend_held))));
    assign read_pend_live = (read_pend_held && !pend_release) || (drq_by_read && drq_held && !pend_release) ||
                            (second_half && ((drq_by_write && drq_held) ||
                                             (!drq_reset && (drq_by_write || drq_held || drq_by_read))));

    always @(posedge sysclk) begin
        drq_held <= drq_live;
        read_pend_held <= read_pend_live;
        if (bus_data) drq <= 1'b0;                 // a host access to DATA clears DRQ at once
        else if (word_ends) drq <= drq_live;

        if (word_ends) begin
            data <= data_seen;
            if (load_a1) data_shift <= MARK_A1;
            else if (load_c2) data_shift <= MARK_C2;
            else if (byte_write_stb && write_ready) data_shift <= data;
            else data_shift <= {data_shift[6:0], dec_data_cell};
            read_pend <= read_pend_live;
            lost <= lost_seen;
            write_ready <= ((write_drq_off || type1 || !byte_write_stb) && write_ready) || wr_data_en || set_busy;
        end
    end
endmodule
