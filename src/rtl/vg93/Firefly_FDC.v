//------------------------------------------------------------
// Firefly FDC Top Level
//------------------------------------------------------------
//     Firefly
// IanPo, 2020-23
`default_nettype wire

module Firefly_FDC (
// clocks
input          iCLK,
input          iCLK16,
input          iRESET,

// cpu signals
input	[15:0]	iADDR,
input	[7:0]		iDATA,
input				iM1,
input				iWR,
input				iRD,
input				iIORQ,

// DOS
input           iDOS,
input 			 iVDOS,
input           iCSn,
input           iWRFF,

// controller output signals
output          oCS,
output  [7:0]   oDATA,

// Floppy signals
output			oFDC_SIDE1,
input				iFDC_RDATA,
input				iFDC_WPRT,
input				iFDC_TR00,
input				iFDC_INDEX,
output			oFDC_WG,
output			oFDC_WR_DATA,
output			oFDC_STEP,
output			oFDC_DIR,
output			oFDC_MOTOR,
output	[1:0]	oFDC_DS

);

  localparam VGCOM  = 8'h1F;
  localparam VGTRK  = 8'h3F;
  localparam VGSEC  = 8'h5F;
  localparam VGDAT  = 8'h7F;
  localparam VGSYS  = 8'hFF;

/////////////////////////////////////////////////////////////

reg				rIOW, rIOW0;
//
wire rTRDOS;
//
reg		[7:0]	wOUTDATA;		//  
//
//
reg		[4:0]	r_BDI_FF;		//   TR-DOS () : D0,D1 -  , D2 - wVG_RESET_n, D3 - iHRDY, D4 - /SIDE1
//
reg				rDRQ_R_DREG;	//  DRQ     
reg				r2RQ_R_SREG;	//  INTRQ  DRQ    
//
reg				r_BDI_DRQ, r_BDI_DRQ0;
reg				r_BDI_INTRQ, r_BDI_INTRQ0;
//
wire			wROMADR;
//
wire			wIOR;
//
wire	[4:0]	wPORTSBits;
//
////////////////////////////////////////////////////////////////
wire			wVFOE;		// 1 -  , 0 - 
wire			wWG;		// write gate
//
wire	[3:0]	wIP_CNT;
wire			wRAWR;
wire			wRCLK;
wire 	[47:0]	w3WORDS;
wire			wSYNC;
wire			wSTART;
wire	[7:0]	wBYTE_2_MAIN;
wire			wBYTE_2_READ;
wire	[7:0]	wMAIN_2_BYTE;
wire			wBYTE_2_WRITE;
wire			wTRANSLATE;
wire			wRESET_CRC;		// 1 - , 0 - 
wire	[10:0]	wBYTE_CNT;		//  ,   CRC16_D8
wire	[15:0]	wCRC16_D8;
//
wire 	[7:0]	wDATA_IN;
wire			wNEW_DAT;
//
wire	[11:0]	wSEC_LEN;
wire	[3:0]	wBIN0, wBIN1, wBIN2, wBIN3;
//
wire			wVG_RESET_n;
//
wire			wTG43;
wire			wNEXT_BYTE;
//
wire	[7:0]	w_BDI_DO;
wire			w_BDI_DRQ;
wire			w_BDI_INTRQ;
//
wire			w_BDI_WR_EN;
//
/////////////////////////////////////////////////////////////////

//
assign wROMADR = iADDR[15] | iADDR[14];
//
assign oDATA = wOUTDATA;
reg vgREQ;
assign oCS = (~wIOR) & vgREQ;
//
assign wIOR = iIORQ | iRD;
//
assign oFDC_SIDE1 = !r_BDI_FF[4];
assign oFDC_DS[0] = r_BDI_FF[1:0] == 2'b00;
assign oFDC_DS[1] = r_BDI_FF[1:0] == 2'b01;

//
assign wPORTSBits = { iADDR[15], iADDR[13], iADDR[7], iADDR[1], iADDR[0] };
//
//    BDI #1F-7F
assign w_BDI_WR_EN = ( iCSn | iWR ) == 1'b0;
//
assign oFDC_WG = wWG;
//
assign wVG_RESET_n = r_BDI_FF[2];
//
assign rTRDOS = iDOS;
//
always @( posedge iCLK )
begin
	rIOW0 <= iIORQ | iWR;
	rIOW <= ~rIOW0;
	//
	r_BDI_DRQ0 <= w_BDI_DRQ;
	r_BDI_DRQ <= r_BDI_DRQ0;
	//
	r_BDI_INTRQ0 <= w_BDI_INTRQ;
	r_BDI_INTRQ <= r_BDI_INTRQ0;
	//
end
//
always @( posedge iCLK )
if ( wVG_RESET_n == 1'b0 )
	r2RQ_R_SREG <= 1'b0;
else
	if ( r2RQ_R_SREG == 1'b0 )
		if ( wIOR == 1'b0 && iADDR[7:5] == 3'b000 && rTRDOS == 1'b0 )	//    BDI (STATUS register)
			r2RQ_R_SREG <= 1'b1;
		else	;
	else
		if ( r_BDI_INTRQ == 1'b0 )
			r2RQ_R_SREG <= 1'b0;
//
always @( posedge iCLK )
if ( wVG_RESET_n == 1'b0 )
	rDRQ_R_DREG <= 1'b0;
else
	if ( rDRQ_R_DREG == 1'b0 )
		if ( ( iIORQ | ( iWR & iRD ) ) == 1'b0 && iADDR[7:5] == 3'b011 && rTRDOS == 1'b0 )	// -   BDI (DATA register)
			rDRQ_R_DREG <= 1'b1;
		else	;
	else
		if ( r_BDI_DRQ == 1'b0 )
			rDRQ_R_DREG <= 1'b0;
//
always @( wVG_RESET_n, w_BDI_INTRQ, w_BDI_DRQ, w_BDI_DO, rTRDOS, wIOR, wPORTSBits, iADDR[14], iCSn )	//     
if ( (wIOR == 1'b1) || (iVDOS == 1'b1) )
begin
	wOUTDATA = 8'hFF;
    vgREQ = 1'b0;
end
else
begin

	if ((iADDR[7:0] == VGSYS))
	begin
		wOUTDATA = { w_BDI_INTRQ, w_BDI_DRQ, 6'b111111 };
		vgREQ = 1'b1;
	end
	else if ( (iCSn == 1'b0) && ((iADDR[7:0] == VGCOM) || (iADDR[7:0] == VGTRK) || (iADDR[7:0] == VGSEC) || (iADDR[7:0] == VGDAT)) ) begin
		wOUTDATA = w_BDI_DO;
      vgREQ = 1'b1;
	end
	else 
		vgREQ = 1'b0;
	
/*	casez ( wPORTSBits )
		5'b??111:	begin 
            if (rTRDOS == 1'b0) begin
              wOUTDATA = { w_BDI_INTRQ, w_BDI_DRQ, 6'h3F }; 
              vgREQ = 1'b1; 
				end
				else
					vgREQ = 1'b0;
        end
		5'b??011:	begin 
            if (iCSn == 1'b0) begin
                wOUTDATA = w_BDI_DO; 
                vgREQ = 1'b1; 
				end
				else
					vgREQ = 1'b0;
			end
		default: vgREQ = 1'b0;
	endcase*/
end
//
always @( posedge iCLK )	//    #FF (TR-DOS)
if ( iRESET )
	begin
		r_BDI_FF <= 5'b0;
	end
else
	if (iWRFF) 
	begin
		r_BDI_FF <= iDATA[4:0];
	end
//
//
//
Main_CTRL U14 (
	.iCLK ( iCLK16 ),
	.iRESETn ( wVG_RESET_n ),
	.iWR_EN ( w_BDI_WR_EN ),
	.iADR ( iADDR[6:5] ),
	.iDATA ( iDATA ),
	.oDATA ( w_BDI_DO ),
//
	.oSTEP ( oFDC_STEP ),
	.oDIRC ( oFDC_DIR ),
	.oHLD ( oFDC_MOTOR ),
	.iHRDY ( r_BDI_FF[3] ),
	.iTR00 ( iFDC_TR00 ),
	.iIP ( iFDC_INDEX ),
	.iWRPT ( iFDC_WPRT ),
	.oWG ( wWG ),
	.oDRQ ( w_BDI_DRQ ),
	.oINTRQ ( w_BDI_INTRQ ),
//
	.iSYNC			( wSYNC ),
	.iBYTE_CNT		( wBYTE_CNT ),
	.iCRC16_D8		( wCRC16_D8 ),
	.oRESET_CRC		( wRESET_CRC ),
	.oVFOE			( wVFOE ),
	.oIP_CNT		( wIP_CNT ),
	.iBYTE_2_MAIN	( wBYTE_2_MAIN ),
	.iBYTE_2_READ	( wBYTE_2_READ ),
	.oMAIN_2_BYTE	( wMAIN_2_BYTE ),
	.oBYTE_2_WRITE	( wBYTE_2_WRITE ),
	.oTRANSLATE		( wTRANSLATE ),
	.iNEXT_BYTE		( wNEXT_BYTE ),
//
	.iDRQ_R_DREG	( rDRQ_R_DREG ),	//  DRQ     
	.i2RQ_R_SREG	( r2RQ_R_SREG )		//  INTRQ  DRQ    
);
//
DPLL U15 (
	.iCLK	( iCLK16 ),
	.iRDDT	( iFDC_RDATA ),
	.oRCLK	( wRCLK ),
	.oRAWR	( wRAWR ),
	.iVFOE	( wVFOE )
);
//
AMD U16 (
	.iCLK		( iCLK16 ),
	.iRCLK		( wRCLK ),
	.iRAWR		( wRAWR ),
	.iVFOE		( wVFOE ),
	.iIP_CNT	( wIP_CNT ),
	.o3WORDS	( w3WORDS ),
	.oSTART		( wSTART ),
	.oSYNC		( wSYNC )
);
//
MFMDEC U17 (
	.iCLK			( iCLK16 ),
	.iRCLK			( wRCLK ),
	.iVFOE			( wVFOE ),
	.iSTART			( wSTART ),
	.iSYNC			( wSYNC ),
	.i3WORDS		( w3WORDS ),
	.oBYTE_2_MAIN	( wBYTE_2_MAIN ),
	.oBYTE_2_READ	( wBYTE_2_READ )
);
//
CRC16_D8 U19 (
	.iCLK			( iCLK16 ),
	.iRESET_CRC		( wRESET_CRC ),
	.iBYTE_2_MAIN	( wBYTE_2_MAIN ),
	.iMAIN_2_BYTE	( wMAIN_2_BYTE ),
	.iBYTE_2_READ	( wBYTE_2_READ ),
	.iBYTE_2_WRITE	( wBYTE_2_WRITE ),
	.oBYTE_CNT		( wBYTE_CNT ),
	.oCRC16_D8		( wCRC16_D8 )
);
//
MFMCDR U20 (
	.iCLK			( iCLK16 ),
	.iRESETn		( wVG_RESET_n ),
	.iWG			( wWG ),
	.iMAIN_2_BYTE	( wMAIN_2_BYTE ),
	.iBYTE_2_WRITE	( wBYTE_2_WRITE ),
	.iTRANSLATE		( wTRANSLATE ),
	.oNEXT_BYTE		( wNEXT_BYTE ),
	.oWDATA			( oFDC_WR_DATA )
);

endmodule
