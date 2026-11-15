//============================================================================
//  Turbosound-FM (the FM part taken out: two YM2149 / AY, the chip select of the TS-FM)
// 
//  Copyright (C) 2018 Ilia Sharin
//  Copyright (C) 2018 Sorgelig
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================


module turbosound
(
	input wire        RESET,	    // Chip RESET (set all Registers to '0', active high)
	input wire        CLK,		 // Global clock
	input wire        CE,        // YM2203 Master Clock enable (3.5 MHz; the PSG runs at half of it)
	input wire        BDIR,	    // Bus Direction (0 - read , 1 - write)
	input wire        BC,		    // Bus control
	input wire  [7:0] DI,	       // Data In
	output wire [7:0] DO,	       // Data Out
	input wire        AY_MODE,

	output wire [7:0] SSG0_AUDIO_A,
	output wire [7:0] SSG0_AUDIO_B,
	output wire [7:0] SSG0_AUDIO_C,

	output wire [7:0] SSG1_AUDIO_A,
	output wire [7:0] SSG1_AUDIO_B,
	output wire [7:0] SSG1_AUDIO_C,

	output wire MIDI_TX
);

reg       RESET_s;
reg       BDIR_s;
reg       BC_s;
reg [7:0] DI_s;

reg       RESET_d;
reg       BDIR_d;
reg       BC_d;
reg [7:0] DI_d;

always @(posedge CLK) begin
	RESET_d <= RESET;
	BDIR_d <= BDIR;
	BC_d <= BC;
	DI_d <= DI;

	RESET_s <= RESET_d;
	BDIR_s <= BDIR_d;
	BC_s <= BC_d;
	DI_s <= DI_d;
end

// AY1 selected by default; an address write of #F8..#FF selects the chip (bit 0) as in the TS-FM,
// bits 1 (status) and 2 (FM) have nothing to select here
reg ay_select = 1;
reg ym_wr     = 0;
reg [7:0] ym_di;
reg old_BDIR = 0;
reg ym_acc = 0;

always @(posedge CLK or posedge RESET_s) begin
	if (RESET_s) begin
		ay_select <= 1;
		ym_acc    <= 0;
		ym_wr     <= 0;
		old_BDIR  <= 0;
	end
	else begin
		ym_wr <= 0;
		old_BDIR <= BDIR_s;
		if (~old_BDIR & BDIR_s) begin
			if(BC_s & &DI_s[7:3]) begin
				ay_select <=  DI_s[0];
				ym_acc    <= 0;
			end
			else if(BC_s) begin
				ym_acc <= !DI_s[7:4];
				ym_wr  <= !DI_s[7:4];
			end
			else begin
				ym_wr <= ym_acc;
			end
			ym_di <= DI_s;
		end
	end
end

// the write of a chip as jt12_top gave it to its ym2149: BDIR = the write, BC = 1 for the address
wire wr0 = ym_wr & ay_select;
wire wr1 = ym_wr & ~ay_select;
wire wr_bc = BC_s;   // ym_wr comes one clock after the BDIR edge, BC_s is still the BC of that write

wire [7:0] DO_0, DO_1;
wire [7:0] port_a;
assign MIDI_TX = port_a[2];

ym2149 psg_0
(
	.CLK(CLK),
	.CE(CE),
	.RESET(RESET_s),
	.BDIR(wr0),
	.BC(wr_bc | ~wr0),
	.DI(ym_di),
	.DO(DO_0),
	.SEL(1'b1),
	.MODE(AY_MODE),
	.ACTIVE(),
	.IOA_in(8'hFF),
	.IOA_out(port_a),
	.IOB_in(8'hFF),
	.IOB_out(),
	.CHANNEL_A(SSG0_AUDIO_A),
	.CHANNEL_B(SSG0_AUDIO_B),
	.CHANNEL_C(SSG0_AUDIO_C)
);

ym2149 psg_1
(
	.CLK(CLK),
	.CE(CE),
	.RESET(RESET_s),
	.BDIR(wr1),
	.BC(wr_bc | ~wr1),
	.DI(ym_di),
	.DO(DO_1),
	.SEL(1'b1),
	.MODE(AY_MODE),
	.ACTIVE(),
	.IOA_in(8'hFF),
	.IOA_out(),
	.IOB_in(8'hFF),
	.IOB_out(),
	.CHANNEL_A(SSG1_AUDIO_A),
	.CHANNEL_B(SSG1_AUDIO_B),
	.CHANNEL_C(SSG1_AUDIO_C)
);

assign DO = ay_select ? DO_0 : DO_1;

endmodule
