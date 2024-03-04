//============================================================================
//  Turbosound-FM
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
	input wire        CE,        // YM2203 Master Clock enable

	input wire        BDIR,	    // Bus Direction (0 - read , 1 - write)
	input wire        BC,		    // Bus control
	input wire  [7:0] DI,	       // Data In
	output wire [7:0] DO,	       // Data Out
	
	input wire        AY_MODE,

	output reg [7:0] SSG0_AUDIO_A,
	output reg [7:0] SSG0_AUDIO_B,
	output reg [7:0] SSG0_AUDIO_C,
	output reg [15:0] SSG0_AUDIO_FM,

	output reg [7:0] SSG1_AUDIO_A,
	output reg [7:0] SSG1_AUDIO_B,
	output reg [7:0] SSG1_AUDIO_C,
	output reg [15:0] SSG1_AUDIO_FM,

	output reg SSG_FM_ENA
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


// AY1 selected by default
reg ay_select = 1;
reg stat_sel  = 1;
reg fm_ena    = 0;
reg ym_wr     = 0;
reg [7:0] ym_di;

reg old_BDIR = 0;
reg ym_acc = 0;
always @(posedge CLK or posedge RESET_s) begin

	if (RESET_s) begin
		ay_select <= 1;
		stat_sel  <= 1;
		fm_ena    <= 0;
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
				stat_sel  <=  DI_s[1];
				fm_ena    <= ~DI_s[2];
				ym_acc    <= 0;
			end
			else if(BC_s) begin
				ym_acc <= !DI_s[7:4] || fm_ena;
				ym_wr  <= !DI_s[7:4] || fm_ena;
			end
			else begin
				ym_wr <= ym_acc;
			end
			ym_di <= DI_s;
		end
	end
end

wire  [7:0] psg_ch_a_0;
wire  [7:0] psg_ch_b_0;
wire  [7:0] psg_ch_c_0;
wire signed [15:0] opn_0;
wire  [7:0] DO_0;

jt03 ym2203_0
(
	.rst(RESET_s),
	.clk(CLK),
	.cen(CE),
	.din(ym_di),
	.addr((BDIR_s|ym_wr) ? ~BC_s : stat_sel),
	.cs_n(ay_select),
	.wr_n(~ym_wr),
	.dout(DO_0),
	.ay_mode(AY_MODE),

	.psg_A(psg_ch_a_0),
	.psg_B(psg_ch_b_0),
	.psg_C(psg_ch_c_0),

	.fm_snd(opn_0)
);

wire  [7:0] psg_ch_a_1;
wire  [7:0] psg_ch_b_1;
wire  [7:0] psg_ch_c_1;
wire signed	[15:0] opn_1;
wire  [7:0] DO_1;

jt03 ym2203_1
(
	.rst(RESET_s),
	.clk(CLK),
	.cen(CE),
	.din(ym_di),
	.addr((BDIR_s|ym_wr) ? ~BC_s : stat_sel),
	.cs_n(~ay_select),
	.wr_n(~ym_wr),
	.dout(DO_1),
	.ay_mode(AY_MODE),

	.psg_A(psg_ch_a_1),
	.psg_B(psg_ch_b_1),
	.psg_C(psg_ch_c_1),

	.fm_snd(opn_1)
);

assign DO = ay_select ? DO_1 : DO_0;

always @(*) begin
	SSG0_AUDIO_A <= psg_ch_a_0;
	SSG0_AUDIO_B <= psg_ch_b_0;
	SSG0_AUDIO_C <= psg_ch_c_0;
	SSG1_AUDIO_A <= psg_ch_a_1;
	SSG1_AUDIO_B <= psg_ch_b_1;
	SSG1_AUDIO_C <= psg_ch_c_1;
	SSG0_AUDIO_FM <= fm_ena ? $signed(opn_0) : 16'b000000000000;
	SSG1_AUDIO_FM <= fm_ena ? $signed(opn_1) : 16'b000000000000;
	SSG_FM_ENA <= fm_ena;
end 

endmodule
