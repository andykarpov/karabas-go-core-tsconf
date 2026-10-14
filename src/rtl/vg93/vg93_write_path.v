// Thanks to deathsoft for the transistor-level schematic of the chip and to titus for the gate-level RTL.
//
// Write data path (sheet data_writer): MFM / FM encoder, write gate, write precompensation.
//
// Each write word produces one data bit (the top bit of the CRC or of DATA_SHIFT, a 0 or a 1). The bit goes through
// a 4-stage pipeline together with the clock bit pipeline (0 = a missing clock pulse of a mark), and WD pulses in
// the write window for the clock and data cells. WG follows "this is a write word" two microwords later. In MFM the
// precompensation outputs EARLY / LATE come from the data pattern around the bit; FM uses the same flops for the
// half cell timing. The special bytes of FORMAT are recognised in vg93_data_channel; here they start the pipelines
// of the missing clocks.
//
// Errata 6 (docs/errata): U167 takes CDAT1 inverted; that is the term "!c1" of the FM late flop below.
module vg93_write_path (
    input  wire sysclk,
    input  wire cell_ends, word_ends,
    input  wire write_window,
    input  wire mfm,
    // decoder
    input  wire write_gate, clock_drop,
    input  wire [1:0] write_src,
    // FORMAT special bytes (data channel)
    input  wire index_mark, format_fm_mark, load_a1, load_c2,
    input  wire shift_msb,                // DATA_SHIFT[7]
    input  wire crc_msb,                  // CRC[15]
    output wire write_bit,                // data bit of this word (also into the CRC)
    output reg  wg = 1'b0,                // WG pin (q257)
    output wire wd,                       // WD pin
    output wire early, late               // EARLY, LATE pins
);
`include "vg93_actions.vh"
    reg  [2:0] index_pipe = 3'd0;         // FCh index mark: missing clocks D7h (q293 q294 q295)
    reg  [2:0] fm_mark_pipe = 3'd0;       // FM mark / clock drop: missing clocks C7h (q299 q300 q301)
    reg  [2:0] mfm_mark_pipe = 3'd0;      // A1h / C2h: the missing clock of the sync byte (q305 q306 q307)
    reg  mfm_clock_drop = 1'b0;           // MFM: drop the clock of this bit (q309)
    reg  [4:0] clock_pipe = 5'd0;         // clock bit pipeline (q314 q315, CDAT0..2 = bits 2..4)
    reg  [3:0] data_pipe = 4'd0;          // data bit pipeline (DATA0..3; q231 q549 q552 q1011)
    reg  no_write_d = 1'b0;               // the last word was not a write word (q255)
    reg  pre_wg = 1'b0;                   // the word before was a write word: WG next (q256)
    reg  mfm_late = 1'b0;                 // MFM precompensation: write this pulse late (q281)
    reg  mfm_early = 1'b0;                // MFM precompensation: write this pulse early (q270)
    reg  cell_half2 = 1'b0;               // second half of the bit cell: the data pulse (q260)
    reg  [1:0] fm_late = 2'd0;            // FM half cell timing (q280 q277)
    reg  [1:0] fm_early = 2'd0;           // (q274 q275)

    reg src_bit;
    always @*
        case (write_src)
        WR_CRC:   src_bit = crc_msb;
        WR_SHIFT: src_bit = shift_msb;
        WR_ZERO:  src_bit = 1'b0;
        default:  src_bit = 1'b1;
        endcase
    assign write_bit = write_gate && src_bit;

    // Missing clocks of the marks: a mark byte starts a pipeline that reaches, word by word, the bits whose clock
    // pulse is dropped (FM marks: clock C7h / D7h; MFM A1h / C2h: the one missing clock of the sync byte), and
    // CLK_DROP drops the clock of its own bit.
    wire fm_drop = fm_mark_pipe[0] || clock_drop;
    wire fm_no_clock = index_pipe[0] || index_pipe[2] || fm_drop || fm_mark_pipe[1] || fm_mark_pipe[2];
    wire clock_on = !((fm_no_clock && !mfm) || (mfm && mfm_clock_drop));

    wire d0 = data_pipe[0], d1 = data_pipe[1], d2 = data_pipe[2], d3 = data_pipe[3];
    wire c0 = clock_pipe[2], c1 = clock_pipe[3], c2 = clock_pipe[4];
    // MFM write precompensation from the bit pattern around the cell (d0 newest): a pulse that follows a 1 and is
    // followed by a 0 is written late, the mirror pattern early, also for clock pulses between 0 bits (U278, U269)
    wire mfm_late_next = (!d0 && !d1 && !d2 && d3 && c0 && c2) || (d0 && d1 && !d2);
    wire mfm_early_next = (d0 && !d1 && !d2 && !d3 && c0 && c2) || (!d0 && d1 && d2);
    // FM: the same flops time the pulse within the half cell
    wire fm_late_next = !mfm && pre_wg && ((d1 && !d2 && !cell_half2) || (cell_half2 && d1 && c0 && !c1));
    wire fm_early_next = !mfm && pre_wg && ((!d1 && d2 && !cell_half2) || (cell_half2 && d1 && !c0 && c1));

    // WD: a pulse in the write window (U264 & WG & /F2). The first half of a bit cell carries the clock pulse - in
    // MFM only between two 0 bits, in FM always - unless the clock is dropped (marks); the second half carries the
    // data pulse of a 1 bit. Only the divider's window: no WD at a read mode cell end.
    wire clock_pulse = c2 && (!mfm || (!d2 && !d3));
    wire wd_cell = cell_half2 ? d2 : clock_pulse;
    assign wd = wd_cell && wg && write_window;
    assign early = mfm_early || fm_early[1];
    assign late = mfm_late || fm_late[1];

    always @(posedge sysclk) begin
        if (word_ends) begin
            index_pipe <= {index_pipe[1:0], index_mark};
            fm_mark_pipe <= {fm_mark_pipe[1], fm_drop, format_fm_mark};
            mfm_mark_pipe <= {mfm_mark_pipe[1], load_c2 || mfm_mark_pipe[0], load_a1};
            mfm_clock_drop <= mfm_mark_pipe[2] || clock_drop;
            clock_pipe <= {clock_pipe[3:0], clock_on};
            data_pipe <= {data_pipe[2:0], write_bit};
            no_write_d <= !write_gate;                // WG follows the write words two words later
            pre_wg <= !no_write_d;
            wg <= pre_wg;
            mfm_late <= mfm_late_next && pre_wg && mfm;
            mfm_early <= mfm_early_next && pre_wg && mfm;
        end
        if (cell_ends) begin                          // half cells of the encoder while writing
            cell_half2 <= pre_wg && !cell_half2;
            fm_late <= {fm_late[0], fm_late_next};
            fm_early <= {fm_early[0], fm_early_next};
        end
    end
endmodule
