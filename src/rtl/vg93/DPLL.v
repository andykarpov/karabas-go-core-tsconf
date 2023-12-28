// IanPo/zx-pk.ru, 2016
// Модуль восстановителя данных (ФАПЧ) для HDL-модели КР1818ВГ93/WD1793
// Основан на схеме от Andromeda Systems из документа WD Corp. FD179X Application Notes Fig.12
//
`default_nettype none
//
module DPLL (
input				iCLK,
input				iRDDT,
output reg			oRCLK,
output				oRAWR,
input				iVFOE
);
//
reg					rRDDT1, rRDDT2;
reg			[4:0]	rPLL_CNT;
wire		[4:0]	w288;
//
initial
begin
	oRCLK = 1'b0;
end
//
always @( posedge iCLK )
begin
	rRDDT1 <= iRDDT;
	rRDDT2 <= ~rRDDT1;
end
//
always @( posedge iCLK )
if ( iVFOE == 1'b1 )
	oRCLK <= 1'b0;
else
	if ( w288 == 5'd16 )
		oRCLK <= ~oRCLK;
//
assign oRAWR = rRDDT1 & rRDDT2 & ~iVFOE;
//
ROMDPLL	U15 (
.address ( { ~oRAWR, w288 } ),
.clock ( iCLK ),
.q ( w288 )
);
//
endmodule
