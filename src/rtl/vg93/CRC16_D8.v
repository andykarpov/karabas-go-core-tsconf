// Copyright (C) 1999-2008 Easics NV.
// Purpose : synthesizable CRC function
//   * polynomial: (0 5 12 16)
//   * data width: 8
//   * convention: the first serial bit is D[7]
// Info : tools@easics.be
//        http://www.easics.com
// Перевел в удобный мне вид IanPo/zx-pk.ru, 2016
//
`default_nettype none
//
module CRC16_D8 (
input			iCLK,
input			iRESET_CRC,
input	[7:0]	iBYTE_2_MAIN,
input	[7:0]	iMAIN_2_BYTE,
input			iBYTE_2_READ,
input			iBYTE_2_WRITE,
output	[10:0]	oBYTE_CNT,
output	[15:0]	oCRC16_D8
);
//
reg		[15:0]	rNEW_CRC;
reg		[10:0]	rBYTE_CNT;
reg				rLAST_2RW;
wire	[7:0]	wNEW_BYTE;
//
initial
begin
	rNEW_CRC = 16'hFFFF;
	rLAST_2RW = 1'b0;
end
//
always @( posedge iCLK )
if ( iRESET_CRC == 1'b1 )
	begin
		rNEW_CRC <= 16'hFFFF;
		rBYTE_CNT <= 11'd0;
		rLAST_2RW <= 1'b0;
	end
else
	if ( ( ( iBYTE_2_READ == 1'b1 ) || ( iBYTE_2_WRITE == 1'b1 ) ) && ( rLAST_2RW == 1'b0 ) )
		begin
			rNEW_CRC[0] <= wNEW_BYTE[4] ^ wNEW_BYTE[0] ^ rNEW_CRC[8] ^ rNEW_CRC[12];
			rNEW_CRC[1] <= wNEW_BYTE[5] ^ wNEW_BYTE[1] ^ rNEW_CRC[9] ^ rNEW_CRC[13];
			rNEW_CRC[2] <= wNEW_BYTE[6] ^ wNEW_BYTE[2] ^ rNEW_CRC[10] ^ rNEW_CRC[14];
			rNEW_CRC[3] <= wNEW_BYTE[7] ^ wNEW_BYTE[3] ^ rNEW_CRC[11] ^ rNEW_CRC[15];
			rNEW_CRC[4] <= wNEW_BYTE[4] ^ rNEW_CRC[12];
			rNEW_CRC[5] <= wNEW_BYTE[5] ^ wNEW_BYTE[4] ^ wNEW_BYTE[0] ^ rNEW_CRC[8] ^ rNEW_CRC[12] ^ rNEW_CRC[13];
			rNEW_CRC[6] <= wNEW_BYTE[6] ^ wNEW_BYTE[5] ^ wNEW_BYTE[1] ^ rNEW_CRC[9] ^ rNEW_CRC[13] ^ rNEW_CRC[14];
			rNEW_CRC[7] <= wNEW_BYTE[7] ^ wNEW_BYTE[6] ^ wNEW_BYTE[2] ^ rNEW_CRC[10] ^ rNEW_CRC[14] ^ rNEW_CRC[15];
			rNEW_CRC[8] <= wNEW_BYTE[7] ^ wNEW_BYTE[3] ^ rNEW_CRC[0] ^ rNEW_CRC[11] ^ rNEW_CRC[15];
			rNEW_CRC[9] <= wNEW_BYTE[4] ^ rNEW_CRC[1] ^ rNEW_CRC[12];
			rNEW_CRC[10] <= wNEW_BYTE[5] ^ rNEW_CRC[2] ^ rNEW_CRC[13];
			rNEW_CRC[11] <= wNEW_BYTE[6] ^ rNEW_CRC[3] ^ rNEW_CRC[14];
			rNEW_CRC[12] <= wNEW_BYTE[7] ^ wNEW_BYTE[4] ^ wNEW_BYTE[0] ^ rNEW_CRC[4] ^ rNEW_CRC[8] ^ rNEW_CRC[12] ^ rNEW_CRC[15];
			rNEW_CRC[13] <= wNEW_BYTE[5] ^ wNEW_BYTE[1] ^ rNEW_CRC[5] ^ rNEW_CRC[9] ^ rNEW_CRC[13];
			rNEW_CRC[14] <= wNEW_BYTE[6] ^ wNEW_BYTE[2] ^ rNEW_CRC[6] ^ rNEW_CRC[10] ^ rNEW_CRC[14];
			rNEW_CRC[15] <= wNEW_BYTE[7] ^ wNEW_BYTE[3] ^ rNEW_CRC[7] ^ rNEW_CRC[11] ^ rNEW_CRC[15];
			rBYTE_CNT <= rBYTE_CNT + 1'b1;
			rLAST_2RW <= 1'b1;
		end
	else
		rLAST_2RW <= 1'b0;
//
assign oCRC16_D8 = rNEW_CRC;
assign oBYTE_CNT = rBYTE_CNT;
assign wNEW_BYTE = iBYTE_2_READ == 1'b1 ? iBYTE_2_MAIN : iMAIN_2_BYTE;
//
endmodule
