// IanPo/zx-pk.ru, 2016
//    ()  HDL- 181893/WD1793
//     Andromeda Systems   WD Corp. FD179X Application Notes Fig.12
//
`default_nettype wire
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
reg		[4:0]	w288;
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

reg [5:0] mem[0:63];
initial begin
  $readmemh ("DPLL.hex", mem, 0);
end
always @(posedge iCLK) begin
 w288 <= mem[{ ~oRAWR, w288 }];
end

//
endmodule
