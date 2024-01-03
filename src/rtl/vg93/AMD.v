// IanPo/zx-pk.ru, 2016
//     ()  HDL- 181893/WD1793
//  48-   (   )
//
`default_nettype wire
//
module AMD (
input				iCLK,
input				iRCLK,
input				iRAWR,
input				iVFOE,
input		[3:0]	iIP_CNT,
output reg	[47:0]	o3WORDS,
output reg			oSTART,
output				oSYNC
);
//
reg					rBIT;
reg					rRCLK1;
//
initial
begin
	oSTART = 1'b0;
end
//
always @( posedge iCLK )
//if ( ( iVFOE == 1'b1 ) || ( iIP_CNT == 4'b0 ) )
if ( iVFOE == 1'b1 )
	oSTART <= 1'b0;
else
	if ( ( oSTART == 1'b0 ) && ( oSYNC == 1'b1 ) )	oSTART <= 1'b1;
//
always @( posedge iCLK )
rRCLK1 <= iRCLK;
//
always @( posedge iCLK )
if ( iVFOE == 1'b0 )
	if ( rRCLK1 != iRCLK )
		begin
			o3WORDS <= { o3WORDS[46:0], rBIT };
			rBIT <= 1'b0;
		end
	else
		if ( iRAWR == 1'b1 )
			rBIT <= 1'b1;
//
assign oSYNC = ( { o3WORDS[46:0], rBIT } == 48'h522452245224 ) || ( { o3WORDS[46:0], rBIT } == 48'h448944894489 );
//
endmodule
