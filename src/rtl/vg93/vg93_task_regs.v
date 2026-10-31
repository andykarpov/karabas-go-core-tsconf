// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// The registers of a command (sheets cmd_reg, trk_reg, sect_reg, serial_inc_dec, ser_comp): command register OP,
// track register TRK, sector register SEC, and the serial ALU that steps TRK and compares numbers.
//
// The microprogram works on TRK / SEC one bit per microword: TRK_ROL / SEC_ROL rotate a register left through
// the serial incrementer (the bit leaving at the top comes back in at the bottom, plus the carry), TRK_SH0 /
// TRK_SH1 shift a 0 / 1 in, SEC_READ shifts in a bit read from the disk, the comparator walks two operands bit by
// bit (track / sector of an ID field against TRK / SEC: CMP_MATCH jumps on a difference). This bit-serial behaviour
// is visible to the host (a read in the middle of an operation shows the partial value), so it stays.
//
// TRK and SEC load at the word end. In the second half of the word the chip's register latch is already open: the
// host reads the value being formed (a shifted bit, a byte the host is writing - REG_DAL_IN follows the bus during
// a write): track_seen, sector_seen. Sources that coincide (a host write during a shift) meet in a wired AND.
module vg93_task_regs (
    input  wire sysclk,
    input  wire word_ends, second_half,
    input  wire mr_s, mr_next,            // MR_S, and the MR_S this word end takes
    // decoder
    input  wire trk_shift, sec_shift,
    input  wire [1:0] trk_fill, sec_fill,
    input  wire ser_inc, ser_inc_force_up, cmp_en,
    input  wire [1:0] cmp_operand,
    // host writes
    input  wire [7:0] dal_in,
    input  wire wr_cmd_en, wr_trk_en, wr_sec_en,
    // data path
    input  wire byte_stb, ser_inc_sync,   // byte strobe, first word of a serial increment run (counters)
    input  wire rd_data,                  // the data bit read in the last data cell
    input  wire shift_msb,                // DATA_SHIFT[7]
    input  wire dirc,                     // DIRC: the incrementer counts up
    output reg  [7:0] cmd_reg = 8'd0,     // OP
    output wire host_int_cmd,             // OP holds an interrupt command D0h..DFh (U57)
    output wire [3:0] int_conditions,     // OP bits 3..0 of an interrupt command (status)
    output wire [7:0] track_seen,         // TRK / SEC as the host reads them
    output wire [7:0] sector_seen,
    output reg  cmp_differ = 1'b0,        // a bit differed (U569): CMP_MATCH jumps on it
    output reg  cmp_greater = 1'b0        // the last differing bit (U584): TG43 / DIRC update
);
`include "vg93_actions.vh"
`include "vg93_common.vh"
    localparam [3:0] OP_FORCE_INT = 4'hD;     // D0h..DFh: FORCE INTERRUPT
    localparam [7:0] SEC_AT_RESET = 8'h01;    // MR_S holds SEC at 01h

    reg  [7:0] track = 8'd0;                  // TRK: the value the microword works on
    reg  [7:0] sector = 8'd0;                 // SEC
    reg  inc_carry = 1'b0;                    // carry of the serial incrementer
    reg  cmp_en_d = 1'b0;                     // the comparator ran in the last word (U580)

    assign host_int_cmd = cmd_reg[7:4] == OP_FORCE_INT;
    assign int_conditions = cmd_reg[3:0];

    // ---- serial ALU ----
    wire serial_bit = (track[7] && trk_shift) || (sector[7] && sec_shift);   // the bit leaving the register
    wire inc_out = (inc_carry && byte_stb) != serial_bit;                     // carry added at the lowest bit
    wire inc_up = ser_inc_force_up || dirc;
    wire carry_propagates = inc_up == serial_bit;
    reg  cmp_bit;
    always @*
        case (cmp_operand)
        CMP_ZERO:      cmp_bit = 1'b0;
        CMP_ONE:       cmp_bit = 1'b1;
        CMP_SHIFT_MSB: cmp_bit = shift_msb;
        default:       cmp_bit = rd_data;
        endcase
    wire cmp_operand_bit = cmp_bit && cmp_en;
    wire cmp_update = cmp_en && !(cmp_en_d && cmp_differ);   // stops at the first difference

    function fill_bit(input [1:0] fill, input inc, input rd);
        fill_bit = fill == FILL_ONE || (fill == FILL_INC_OUT && inc) || (fill == FILL_RD_DATA && rd);
    endfunction

    // ---- TRK, SEC ----
    wire [7:0] trk_shifted = {track[6:0], fill_bit(trk_fill, inc_out, rd_data)};
    wire [7:0] sec_shifted = {sector[6:0], fill_bit(sec_fill, inc_out, rd_data)};
    wire [7:0] track_next = wired_and(track, wr_trk_en, dal_in, trk_shift, trk_shifted);
    // SEC in the track form: the two sources AND-ed (sec_src), then one choice per bit: /MR, a source, or hold
    wire [7:0] sec_src;
    assign sec_src = (wr_sec_en ? dal_in : 8'hFF) & (sec_shift ? sec_shifted : 8'hFF);
    wire sec_mr = second_half && mr_s;
    wire sec_load = second_half && (wr_sec_en || sec_shift);
    assign track_seen = second_half ? track_next : track;
    assign sector_seen = sec_mr ? SEC_AT_RESET : sec_load ? sec_src : sector;

    // ---- OP: /MR (MR_S in the second half) clears bits 7..2 at once; the host write loads it at the word end; bits
    // 1..0 are preset at the word end by the new MR_S and by the old one, which holds for a moment after the end ----
    reg  [7:0] cmd_now;
    always @* begin
        cmd_now = cmd_reg;
        if (second_half && mr_s) cmd_now[7:2] = 6'd0;
        if (word_ends) begin
            if (wr_cmd_en) cmd_now = dal_in;
            if (mr_next || mr_s) cmd_now[1:0] = 2'b11;
        end
    end

    always @(posedge sysclk) begin
        cmd_reg <= cmd_now;
        if (word_ends) begin
            track <= track_seen;
            sector <= mr_next ? SEC_AT_RESET : sector_seen;

            inc_carry <= (inc_carry && !byte_stb) || ser_inc_sync ||
                         (byte_stb && carry_propagates && inc_carry && ser_inc);
            cmp_differ <= ((cmp_operand_bit != serial_bit) && cmp_en) || (!cmp_update && cmp_differ);
            cmp_greater <= (cmp_greater && !cmp_update) || (cmp_update && cmp_operand_bit);
            cmp_en_d <= cmp_en;
        end
    end
endmodule
