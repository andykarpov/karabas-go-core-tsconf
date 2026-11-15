// ============================================================================
// FM part of the YMF278B (OPL3 compatible) for the U16 OPL4
//
// The synthesis is opl3_fpga by Greg Taylor (LGPL-3, see COPYING.LESSER,
// taken from ao486_MiSTer, channels.sv adapted). This wrapper runs it in the
// 28 MHz domain and talks to opl4_u16 (84 MHz) through toggles:
//   wr_tgl   - a register write: wr_word = {bank, address[7:0], data[7:0]}
//              (held by the sender until the next toggle)
//   tick_tgl - start of one FM sample (159 clocks of 28 MHz)
//   out_l/r  - sums of FM outputs A/B of the last finished sample, change
//              about 6 us after a tick and stay until the next one
// After reset all registers are written once: zero, except TL = 3F and
// RR = F so that a note playing before the reset dies away.
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module opl3_fm
    import opl3_pkg::*;
(
    input  wire        clk,         // 28 MHz
    input  wire        reset_a,     // from the other domain, long
    input  wire        wr_tgl,
    input  wire [16:0] wr_word,
    input  wire        tick_tgl,
    output logic signed [19:0] out_l = 0,
    output logic signed [19:0] out_r = 0
);
    logic [1:0] rst_s = 2'b11;
    logic       reset;
    always_ff @(posedge clk) rst_s <= {rst_s[0], reset_a};
    assign reset = rst_s[1];

    logic [2:0] wr_s = 0, tick_s = 0;
    always_ff @(posedge clk) begin
        wr_s   <= {wr_s[1:0], wr_tgl};
        tick_s <= {tick_s[1:0], tick_tgl};
    end
    wire wr_ev   = wr_s[2] ^ wr_s[1];
    wire tick_ev = tick_s[2] ^ tick_s[1];

    // reset sequencer: 512 writes after reset
    logic [9:0] init_cnt = 0;   // bit 9 = done
    always_ff @(posedge clk)
        if (reset)              init_cnt <= 0;
        else if (!init_cnt[9])  init_cnt <= init_cnt + 1'd1;

    wire [7:0] ia = init_cnt[7:0];
    wire [7:0] init_data = (ia >= 8'h40 && ia <= 8'h55) ? 8'h3f :
                           (ia >= 8'h80 && ia <= 8'h95) ? 8'h0f : 8'h00;

    opl3_reg_wr_t reg_wr;
    always_ff @(posedge clk) begin
        reg_wr <= 0;
        if (!init_cnt[9] && !reset) begin
            reg_wr.valid    <= 1;
            reg_wr.bank_num <= init_cnt[8];
            reg_wr.address  <= ia;
            reg_wr.data     <= init_data;
        end else if (wr_ev && !reset) begin
            reg_wr.valid    <= 1;
            reg_wr.bank_num <= wr_word[16];
            reg_wr.address  <= wr_word[15:8];
            reg_wr.data     <= wr_word[7:0];
        end
    end

    logic acc_valid;
    logic signed [19:0] acc_l, acc_r;

    channels channels (
        .clk,
        .reset,
        .opl3_reg_wr(reg_wr),
        .sample_clk_en(tick_ev && init_cnt[9]),
        .acc_valid,
        .acc_l,
        .acc_r
    );

    always_ff @(posedge clk)
        if (reset) begin
            out_l <= 0;
            out_r <= 0;
        end else if (acc_valid) begin
            out_l <= acc_l;
            out_r <= acc_r;
        end
endmodule
`default_nettype wire
