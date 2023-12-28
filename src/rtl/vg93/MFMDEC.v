// IanPo/zx-pk.ru, 2016
// Модуль декодера MFM для HDL-модели КР1818ВГ93/WD1793
//
`default_nettype none
//
module MFMDEC (
input				iCLK,
input				iRCLK,
input				iVFOE,
input				iSTART,
input				iSYNC,
input		[47:0]	i3WORDS,
output reg	[7:0]	oBYTE_2_MAIN,
output reg			oBYTE_2_READ
);
//
reg					rMFMBIT;
reg					rRCLK1;
reg			[2:0]	rBIT_CNT, rBIT_CNT1;
reg			[7:0]	rCURR_BYTE;
//
initial
begin
	rMFMBIT = 1'b0;
	rBIT_CNT = 3'b0;
	oBYTE_2_READ = 1'b0;
end
//
always @( posedge iCLK )
begin
	rBIT_CNT1 <= rBIT_CNT;
	rRCLK1 <= iRCLK;
end
//
always @( posedge iCLK )
if ( ( iSTART == 1'b0 ) || ( iSYNC == 1'b1 ) )
	rBIT_CNT <= 3'b0;
else
	if ( rRCLK1 != iRCLK )
		begin
			if ( rMFMBIT == 1'b0 )
				begin
					if ( i3WORDS[46] == 1'b1 )
						rCURR_BYTE <= { rCURR_BYTE[6:0], 1'b1 };
					else
						rCURR_BYTE <= { rCURR_BYTE[6:0], 1'b0 };
					rBIT_CNT <= rBIT_CNT + 1'b1;
				end
		end
//
always @( posedge iCLK )
if ( ( iSTART == 1'b0 ) || ( iSYNC == 1'b1 ) )
	rMFMBIT <= 1'b0;
else
	if ( rRCLK1 != iRCLK )
		rMFMBIT <= ~rMFMBIT;
//
always @( posedge iCLK )
if ( iSTART == 1'b0 )
	oBYTE_2_READ <= 1'b0;
else
	if ( ( rBIT_CNT == 3'd0 ) && ( rBIT_CNT1 == 3'd7 ) && ( iSYNC != 1'b1 ) )
		begin
			oBYTE_2_READ <= 1'b1;
			oBYTE_2_MAIN <= rCURR_BYTE;
		end
	else
		oBYTE_2_READ <= 1'b0;
//
endmodule
