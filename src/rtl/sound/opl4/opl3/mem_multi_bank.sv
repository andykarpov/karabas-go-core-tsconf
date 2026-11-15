/*******************************************************************************
#   +html+<pre>
#
#   FILENAME: mem_multi_bank.sv
#   AUTHOR: Greg Taylor     CREATION DATE: 1 April 2024
#
#   DESCRIPTION:
#
#   CHANGE HISTORY:
#   1 April 2024    Greg Taylor
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
`default_nettype none

// U16: one RAM for all banks (bank = top address bits) instead of one per
// bank, so that a memory takes one M9K, and two extra parameters:
//   SYNC  = 1 with OUTPUT_DELAY = 0: dob = word at the address of the
//           previous clock (an M9K read); the readers hold the address for
//           two clocks (operator slots) and take the data in the second
//   LOGIC = 1: keep it in registers (small register files)
// OUTPUT_DELAY 0 without SYNC is an asynchronous read, which an M9K cannot
// do, so it ends up in registers as well.
module mem_multi_bank #(
    parameter DATA_WIDTH = 0,
    parameter DEPTH = 0,
    parameter OUTPUT_DELAY = 0, // 0, 1, or 2
    parameter DEFAULT_VALUE = 0,
    parameter NUM_BANKS = 0,
    parameter BANK_WIDTH = $clog2(NUM_BANKS),
    parameter SYNC = 0,
    parameter LOGIC = 0
) (
    input wire clk,
    input wire wea,
    input wire reb, // only used if OUTPUT_DELAY >0
    input wire [BANK_WIDTH-1:0] banka,
    input wire [$clog2(DEPTH)-1:0] addra,
    input wire [BANK_WIDTH-1:0] bankb,
    input wire [$clog2(DEPTH)-1:0] addrb,
    input wire [DATA_WIDTH-1:0] dia,
    output logic [DATA_WIDTH-1:0] dob
);
    localparam AW = $clog2(DEPTH);
    localparam WORDS = NUM_BANKS << AW;
    localparam logic [DATA_WIDTH-1:0] DEF = DEFAULT_VALUE;

    wire [BANK_WIDTH+AW-1:0] wa = {banka, addra};
    wire [BANK_WIDTH+AW-1:0] ra = {bankb, addrb};
    logic [DATA_WIDTH-1:0] q;
    logic [DATA_WIDTH-1:0] dob_p1 = DEF;
    logic [DATA_WIDTH-1:0] dob_p2 = DEF;

    generate
    if (LOGIC || (OUTPUT_DELAY == 0 && !SYNC)) begin: regs
        (* ramstyle = "logic" *) logic [DATA_WIDTH-1:0] ram [0:WORDS-1];
        initial for (int k = 0; k < WORDS; k++) ram[k] = DEF;
        always_ff @(posedge clk)
            if (wea)
                ram[wa] <= dia;
        if (OUTPUT_DELAY == 0 && SYNC) begin
            logic [DATA_WIDTH-1:0] q_r = DEF;
            always_ff @(posedge clk) q_r <= ram[ra];
            always_comb q = q_r;
        end else
            always_comb q = ram[ra];
        if (OUTPUT_DELAY != 0)
            always_ff @(posedge clk)
                if (reb)
                    dob_p1 <= ram[ra];
    end else begin: m9k
        (* ramstyle = "M9K" *) logic [DATA_WIDTH-1:0] ram [0:WORDS-1];
        initial for (int k = 0; k < WORDS; k++) ram[k] = DEF;
        always_ff @(posedge clk)
            if (wea)
                ram[wa] <= dia;
        if (OUTPUT_DELAY == 0) begin
            // no power-up value here: Quartus folds this register into the
            // M9K address register only if it has none (v23 got the
            // envelope memory in 845 registers because of it)
            logic [DATA_WIDTH-1:0] q_r;
            always_ff @(posedge clk) q_r <= ram[ra];
            always_comb q = q_r;
        end else begin
            always_comb q = '0;
            always_ff @(posedge clk)
                if (reb)
                    dob_p1 <= ram[ra];
        end
    end
    endgenerate

    always_ff @(posedge clk)
        dob_p2 <= dob_p1;

    always_comb
        if (OUTPUT_DELAY == 0)      dob = q;
        else if (OUTPUT_DELAY == 1) dob = dob_p1;
        else                        dob = dob_p2;
endmodule
`default_nettype wire

// U16: simple dual port RAM with 8-bit byte lanes (one M9K), registered read:
// q is the word at ra of the previous clock. For Quartus it is an altsyncram
// with byteena: the inferred version came out as one M9K per lane.
`default_nettype none
module opl3_ram_be #(
    parameter LANES = 4,
    parameter AW = 6
) (
    input wire clk,
    input wire [LANES-1:0] be,
    input wire [AW-1:0] wa,
    input wire [LANES*8-1:0] wd,
    input wire [AW-1:0] ra,
    output logic [LANES*8-1:0] q
);
`ifdef VERILATOR
    logic [LANES-1:0][7:0] ram [0:2**AW-1];
    initial for (int k = 0; k < 2**AW; k++) ram[k] = '0;
    initial q = '0;

    always_ff @(posedge clk) begin
        for (int i = 0; i < LANES; i++)
            if (be[i])
                ram[wa][i] <= wd[i*8 +: 8];
        q <= ram[ra];
    end
`elsif ALTERA_RESERVED_QIS
    altsyncram #(
        .operation_mode("DUAL_PORT"),
        .intended_device_family("Cyclone IV E"),
        .ram_block_type("M9K"),
        .lpm_type("altsyncram"),
        .width_a(LANES*8),
        .widthad_a(AW),
        .numwords_a(2**AW),
        .width_byteena_a(LANES),
        .byte_size(8),
        .width_b(LANES*8),
        .widthad_b(AW),
        .numwords_b(2**AW),
        .address_reg_b("CLOCK0"),
        .rdcontrol_reg_b("CLOCK0"),
        .outdata_reg_b("UNREGISTERED"),
        .outdata_aclr_b("NONE"),
        .address_aclr_b("NONE"),
        .clock_enable_input_a("BYPASS"),
        .clock_enable_input_b("BYPASS"),
        .clock_enable_output_b("BYPASS"),
        .read_during_write_mode_mixed_ports("DONT_CARE"),
        .power_up_uninitialized("FALSE")
    ) ram (
        .clock0(clk),
        .wren_a(|be),
        .byteena_a(be),
        .address_a(wa),
        .data_a(wd),
        .address_b(ra),
        .q_b(q)
    );
`else
    // Karabas Go (XST): one memory per byte lane, each with its own write
    // enable, so XST needs no byte-write inference
    genvar l;
    for (l = 0; l < LANES; l = l + 1) begin: lane
        logic [7:0] ram [0:2**AW-1];
        logic [7:0] q_l;
        always_ff @(posedge clk) begin
            if (be[l])
                ram[wa] <= wd[l*8 +: 8];
            q_l <= ram[ra];
        end
        assign q[l*8 +: 8] = q_l;
    end
`endif
endmodule
`default_nettype wire
