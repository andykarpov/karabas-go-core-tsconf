// IanPo/zx-pk.ru, 2017
//   MFM    HDL- 181893/WD1793
//
`default_nettype wire
//
module MFMCDR (
input				iCLK,			//  16 
input				iRESETn,		//  (    !!! )
input				iWG,			// WRITE GATE
input	[7:0]		iMAIN_2_BYTE,	//  
input				iBYTE_2_WRITE,	//   
input				iTRANSLATE,		//    (  C2, A1 )
output	reg			oNEXT_BYTE,		//   
output	reg			oWDATA
);
//
reg		[2:0]		rBIT_CNT;	//   
reg		[1:0]		rMFM_BIT;	// 2  MFM,   1  
reg		[5:0]		rWDATA_CNT, rWDATA_CNT_MAX;	//  2- 
reg					rMFM_CNT;	//   ( 2  MFM )
wire				wMFM_MSK;	//    C2, A1
reg		[2:0]		rLASTBITS;	//    Late, Early
reg		[7:0]		rMAIN_2_BYTE;
//
parameter
	TWO_mks	= 6'd31,			//  2-  (32  16 )
	HLF_mks	= 6'd8,				// 500  -  
	NXT_byt = HLF_mks + 6'd2;	//   NEXT_BYTE  
//
initial
	begin
		oWDATA 			= 1'b0;
		rBIT_CNT		= 3'd7;
		oNEXT_BYTE		= 1'b0;
		rLASTBITS		= 3'b010;	//  rWDATA_CNT_MAX = TWO_mks
		rMFM_BIT		= 2'b00;
		rMFM_CNT		= 1'b0;
		rWDATA_CNT		= TWO_mks;
		rWDATA_CNT_MAX	= TWO_mks;
		rMAIN_2_BYTE	= 8'h4E;
	end
//
always @( posedge iCLK )
if ( iWG == 1'b0 )
	begin
		rBIT_CNT <= 3'd7;
		rWDATA_CNT <= TWO_mks;
		rWDATA_CNT_MAX <= TWO_mks;
		rMFM_BIT <= 2'b10;
		rMFM_CNT <= 1'b0;
		rMAIN_2_BYTE <= iMAIN_2_BYTE;
	end
else
	begin
		if ( rWDATA_CNT < rWDATA_CNT_MAX )
			rWDATA_CNT <= rWDATA_CNT + 1'b1;
		else
			begin
				rWDATA_CNT <= 5'b0;
				rMFM_CNT <= ~rMFM_CNT;
				casex ( { rLASTBITS, rMAIN_2_BYTE[ rBIT_CNT ] } )
					4'b?110, 4'b0001:	rWDATA_CNT_MAX <= TWO_mks - 6'd1;
					4'b?011, 4'b1000:	rWDATA_CNT_MAX <= TWO_mks + 6'd1;
					default:	rWDATA_CNT_MAX <= TWO_mks;
				endcase
				if ( rMFM_CNT == 1'b1 )
					begin
						rBIT_CNT <= rBIT_CNT - 1'b1;
						if ( ( rBIT_CNT == 3'd0 ) && ( rMFM_CNT == 1'b1 ) )	rMAIN_2_BYTE <= iMAIN_2_BYTE;
						rLASTBITS <= { rLASTBITS[1:0], rMAIN_2_BYTE[ rBIT_CNT ] };
						case ( { rMAIN_2_BYTE[ rBIT_CNT ], rLASTBITS[0] } )
							2'b00:	rMFM_BIT <= { wMFM_MSK, 1'b0 };
							2'b01:	rMFM_BIT <= 2'b00;
							default:	rMFM_BIT <= 2'b01;
						endcase
					end
			end
	end
//
assign wMFM_MSK = ~( ( iTRANSLATE == 1'b1 ) && ( rBIT_CNT == 3'd2 ) &&
			( ( rMAIN_2_BYTE == 8'hA1 ) || ( rMAIN_2_BYTE == 8'hC2 ) ) );
//
always @( posedge iCLK )
if ( ( iBYTE_2_WRITE == 1'b1 ) || ( iWG == 1'b0 ) )
//if ( ( oNEXT_BYTE == 1'b1 ) || ( iWG == 1'b0 ) )
	oNEXT_BYTE <= 1'b0;
else
	if ( ( rBIT_CNT == 3'b0 ) && ( rWDATA_CNT == NXT_byt ) && ( rMFM_CNT == 1'b1 ) )
		oNEXT_BYTE <= 1'b1;
//
always @( posedge iCLK )
if ( ( iWG == 1'b1 ) && ( rWDATA_CNT < HLF_mks ) && ( rMFM_BIT[ ~rMFM_CNT ] == 1'b1 ) )
	oWDATA <= 1'b1;
else
	oWDATA <= 1'b0;
//
endmodule
