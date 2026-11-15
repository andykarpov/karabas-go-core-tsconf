/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: tremolo.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 2 Nov 2014
#
#   DESCRIPTION:
#
#   CHANGE HISTORY:
#   2 Nov 2014    Greg Taylor
#       Initial version
#
#   Copyright (C) 2014 Greg Taylor <gtaylor@sonic.net>
#
#   This file is part of OPL3 FPGA.
#
#   OPL3 FPGA is free software: you can redistribute it and/or modify
#   it under the terms of the GNU Lesser General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   OPL3 FPGA is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU Lesser General Public License for more details.
#
#   You should have received a copy of the GNU Lesser General Public License
#   along with OPL3 FPGA.  If not, see <http://www.gnu.org/licenses/>.
#
#   Original Java Code:
#   Copyright (C) 2008 Robson Cozendey <robson@cozendey.com>
#
#   Original C++ Code:
#   Copyright (C) 2012  Steffen Ohrendorf <steffen.ohrendorf@gmx.de>
#
#   Some code based on forum posts in:
#   http://forums.submarine.org.uk/phpBB/viewforum.php?f=9,
#   Copyright (C) 2010-2013 by carbon14 and opl3
#
#******************************************************************************/
`timescale 1ns / 1ps
`default_nettype none // disable implicit net type declarations
/* altera message_off 10230 */

module tremolo
    import opl3_pkg::*;
(
    input wire clk,
    input wire sample_clk_en,
    input wire [BANK_NUM_WIDTH-1:0] bank_num,
    input wire [OP_NUM_WIDTH-1:0] op_num,
    input wire dam, // depth of tremolo
    output logic [AM_VAL_WIDTH-1:0] am_val_p2 = 0
);
    localparam PIPELINE_DELAY = 2;

    /*
     * U16: as in Nuked-OPL3 (checked against the die): position 0..209 steps
     * every 64 samples (period 13440 samples, 3.7 Hz), triangle 0..105,
     * shifted down by 2 (DAM = 1, 4.8 dB) or 4 (DAM = 0, 1 dB).
     * The original counted to 13*1024 and took >> 8, a slightly different
     * period and shape.
     */
    logic [5:0] timer = 1;  // stepped after the last slot: one ahead of a step at slot 0
    logic [7:0] pos = 0;
    logic [7:0] tri_v;
    logic [AM_VAL_WIDTH-1:0] am_reg = 0;

    // the value for the next sample is fixed at the end of this one, with the
    // DAM bit of that moment (in Nuked a DAM change shows one sample later)
    always_comb tri_v = pos < 8'd105 ? pos : 8'd210 - pos;

    // LFO step: 15 clocks after the last slot of a sample started, when every
    // stage of the pipeline is done with this sample
    logic [3:0] lfo_cnt = 0;
    logic lfo_upd;
    always_ff @(posedge clk)
        if (sample_clk_en && bank_num == 1 && op_num == 17) lfo_cnt <= 1;
        else if (lfo_cnt != 0)                                lfo_cnt <= lfo_cnt + 1'd1;
    always_comb lfo_upd = lfo_cnt == 4'd15;

    always_ff @(posedge clk)
        if (lfo_upd) begin
            timer <= timer + 1'd1;
            am_reg <= dam ? tri_v[7:2] : {2'd0, tri_v[7:4]};
            if (timer == 6'h3f)
                pos <= pos == 8'd209 ? 8'd0 : pos + 1'd1;
        end

    always_ff @(posedge clk)
        am_val_p2 <= am_reg;
endmodule
`default_nettype wire
