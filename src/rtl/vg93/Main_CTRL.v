//
// IanPo/zx-pk.ru, 2016
//    HDL- 181893/WD1793
//
`default_nettype wire
//
module Main_CTRL (
input				iCLK,
input				iRESETn,
input				iWR_EN,
input		[7:0]	iDATA,		//  
input		[1:0]	iADR,		//     ( )
output		[7:0]	oDATA,
//
output				oSTEP,
output 				oDIRC,
input				iHRDY,
output 				oHLD,
input				iTR00,
input				iIP,
input				iWRPT,
output	reg			oWG,
output 				oDRQ,
output 				oINTRQ,
//
output	reg	[3:0]	oIP_CNT,	//       
input		[7:0]	iBYTE_2_MAIN,
input				iBYTE_2_READ,
output	reg [7:0]	oMAIN_2_BYTE,
output	reg			oBYTE_2_WRITE,
output	reg			oTRANSLATE,	//      (..)
input				iNEXT_BYTE,
input				iSYNC,
input		[10:0]	iBYTE_CNT,
input		[15:0]	iCRC16_D8,
output	reg			oRESET_CRC,
output				oVFOE,
//
input				iDRQ_R_DREG,	//  DRQ     
input				i2RQ_R_SREG		//  INTRQ  DRQ    
);
//
reg				rDRQ_R_DREG, rDRQ_R_DREG0;
reg				r2RQ_R_SREG, r2RQ_R_SREG0;
//
reg				rRESETn1, rRESETn2;
reg				rWR_EN, rWR_EN0;
//
reg				rHRDY1, rHRDY2;
reg				rTR001, rTR002;
reg				rIP1, rIP2, rIP3;
reg				rWRPT1, rWRPT2;
//
reg		[3:0]	rIP_CNT_IDLE;	//   IP     (    15 )
//
reg		[7:0]	rREG_CMD, rREG_TRK, rREG_SEC, rREG_DAT;	// 0, 1, 2, 3
reg		[7:0]	REG_STA;	// 0
reg				rBUSY;
reg				rCRC_ERROR;
reg				rSEEK_ERROR;
reg				rLOST_DATA;
reg				rREC_NOT_FOUND;
reg				rWRITE_FAULT;
reg				rREC_TYPE;
//
reg				rDIRC;
reg				rHLD;
reg				rDRQ;
reg				rINTRQ;
//
reg				rHEAD_IN_POS;	// 1 =        
//
reg		[7:0]	rREG_SHF;
reg		[7:0]	rDATA_OUT;
reg		[7:0]	rDATA_IN;
reg		[2:0]	rCURR_STATE, rLAST_CURR_STATE;
reg		[3:0]	rSTEP_CNT;		// ( 3,5"  0.8 )  15 
reg				rSTEP_SET;		//  -  ,  - 
reg				rSTEP_SET0;
reg		[10:0]	rPREDELAY_CNT;	// 2048  iCLK ()
reg		[7:0]	rCNT_AMNT;		//    
reg		[7:0]	rDELAY_CNT;		//  (30 )..(6 )
reg				rDELAY_SET;		//  -  ,  - 
reg				rDELAY_SET0;
reg		[5:0]	rSTAGE;		//   
reg		[7:0]	rREAD_H_CRC;	//   CRC   (  , )
reg		[15:0]	rSAVED_CRC;		//     CRC ()   
reg		[10:0]	rSEC_LEN;		//    
reg				rLAST_MAIN_2_BYTE;	//    1 (  CRC)
//
reg				rINTRQ_R_CMD, rINTRQ_R_CMD1;	//  INTRQ   
reg				rINTRQ_S_CMD, rINTRQ_S_CMD1;	//  INTRQ   
reg				rINTRQ_S_FINT, rINTRQ_S_FINT1;	//  INTRQ   
//
reg				rDRQ_S_CMD;		//  DRQ  (/ )
reg				rDRQ_R_CMD;		//  DRQ 
//
reg				rIPTRG, rIPTRG0;
//
wire			wCPRDY;
//
parameter
	DELAY30	= 8'd234,
	DELAY20	= 8'd156,
	DELAY12	= 8'd94,
	DELAY6	= 8'd47;
//
parameter
	IDLE	= 3'd0,
	TYPE1	= 3'd1,
	TYPE2	= 3'd2,
	TYPE3RD	= 3'd3,
	TYPE3WR	= 3'd4,
	FRC_INT	= 3'd5;
//
initial
	begin
		rCURR_STATE = IDLE;
		rLAST_CURR_STATE = IDLE;
		rREG_CMD = 8'd0;
		rREG_TRK = 8'b0;
		rREG_SEC = 8'b1;
		rREG_DAT = 8'b0;
		rRESETn1 = 1'b1;
		rRESETn2 = 1'b0;
		rIP1 = 1'b0;
		rIP2 = 1'b1;
		rSTEP_CNT = 4'b0;
		rDELAY_CNT = 8'b0;
		rBUSY = 1'b0;
		rLOST_DATA = 1'b0;
		rDRQ = 1'b0;
		rINTRQ = 1'b0;
		rCRC_ERROR = 1'b0;
		rSEEK_ERROR = 1'b0;
		rWRITE_FAULT = 1'b0;
		rREC_TYPE = 1'b0;
		rREC_NOT_FOUND = 1'b0;
		rSTEP_SET = 1'b0;
		rSTEP_SET0 = 1'b0;
		rDELAY_SET = 1'b0;
		rDELAY_SET = 1'b0;
		oRESET_CRC = 1'b0;
		oIP_CNT = 4'b0;
		rIP_CNT_IDLE = 4'b0;
		rINTRQ_R_CMD1 = 1'b0;
		rINTRQ_R_CMD = 1'b0;
		rINTRQ_S_CMD1 = 1'b0;
		rINTRQ_S_CMD = 1'b0;
		rINTRQ_S_FINT1 = 1'b0;
		rINTRQ_S_FINT = 1'b0;
		rDRQ_S_CMD = 1'b0;
		rDRQ_R_CMD = 1'b0;
		rHEAD_IN_POS = 1'b0;
		oWG = 1'b0;
	end
//
always @( posedge iCLK )
begin
	rRESETn1 <= iRESETn;
	rRESETn2 <= rRESETn1;
//
	rHRDY1 <= iHRDY;
	rHRDY2 <= rHRDY1;
//
	rTR001 <= iTR00;
	rTR002 <= rTR001;
//
	rWRPT1 <= iWRPT;
	rWRPT2 <= rWRPT1;
//
	rWR_EN0 <= iWR_EN;
	rWR_EN <= ~rWR_EN0;
//
	rSTEP_SET0 <= rSTEP_SET;
end
//
always @( posedge iCLK )
begin
	rIP1 <= iIP;
	rIP2 <= ~rIP1;
//
	if ( ( rIP1 & rIP2 ) == 1'b1 )
		rIPTRG <= ~rIPTRG;
end
//
always @( posedge iCLK )
begin
	if ( ( ( rRESETn1 | rRESETn2 ) == 1'b0 ) || ( rDELAY_SET0 != rDELAY_SET ) || ( rSTEP_SET0 != rSTEP_SET ) )
		rPREDELAY_CNT <= 11'b0;
	else
		rPREDELAY_CNT <= rPREDELAY_CNT + 1'b1;
end
//
always @( posedge iCLK )
begin
	if ( ( rRESETn1 | rRESETn2 ) == 1'b0 )
		begin
			rDELAY_CNT <= 8'b0;
			rDELAY_SET0 <= 1'b0;
		end
	else
		begin
			rDELAY_SET0 <= rDELAY_SET;
			if ( ( rDELAY_SET0 != rDELAY_SET ) || ( rSTEP_SET0 != rSTEP_SET ) )
				rDELAY_CNT <= rCNT_AMNT;
			else
				if ( ( rDELAY_CNT > 0 ) && ( rPREDELAY_CNT == 11'b11111111111 ) )	rDELAY_CNT <= rDELAY_CNT - 1'b1;
		end
end
//
always @( posedge iCLK )
begin
	if ( ( rRESETn1 | rRESETn2 ) == 1'b0 )
		rSTEP_CNT <= 4'b0;
	else
		if ( rSTEP_SET0 != rSTEP_SET )
			rSTEP_CNT <= 4'd15;
		else
			if ( rSTEP_CNT > 0 )
				rSTEP_CNT <= rSTEP_CNT - 1'b1;
end
//
always @( posedge iCLK )
if ( oVFOE == 1'b1 )
	oIP_CNT <= 4'b0;
else
	if ( ( rIP1 & rIP2 ) == 1'b1 )
		if ( oIP_CNT < 4'b1111 )
			oIP_CNT <= oIP_CNT + 1'b1;
//
always @( posedge iCLK )
if ( rCURR_STATE != IDLE )
	rIP_CNT_IDLE <= 4'b0;
else
	if ( ( rIP1 & rIP2 ) == 1'b1 )
		if ( rIP_CNT_IDLE < 4'b1111 )
			rIP_CNT_IDLE <= rIP_CNT_IDLE + 1'b1;
//
always @( posedge iCLK )
if ( ( rRESETn1 | rRESETn2 ) == 1'b0 )
	begin
		r2RQ_R_SREG <= 1'b0;
		r2RQ_R_SREG0 <= 1'b0;
		rDRQ_R_DREG <= 1'b0;
		rDRQ_R_DREG0 <= 1'b0;
	end
else
	begin
		r2RQ_R_SREG0 <= i2RQ_R_SREG;	//   
		r2RQ_R_SREG <= r2RQ_R_SREG0;
		//
		rDRQ_R_DREG0 <= iDRQ_R_DREG;	// -  
		rDRQ_R_DREG <= rDRQ_R_DREG0;
	end
//
always @( posedge iCLK )
if ( ( rRESETn1 | rRESETn2 ) == 1'b0 )
	rDRQ <= 1'b0;
else
//	if ( r2RQ_R_SREG == 1'b1 || rDRQ_R_DREG == 1'b1 || rDRQ_R_CMD == 1'b1 )
	if ( rDRQ_R_DREG == 1'b1 || rDRQ_R_CMD == 1'b1 )
		rDRQ <= 1'b0;
else
	if ( rDRQ_S_CMD == 1'b1 )
		rDRQ <= 1'b1;
//
always @( posedge iCLK )
if ( ( rRESETn1 | rRESETn2 ) == 1'b0 )
	begin
		rINTRQ_R_CMD1 <= 1'b0;
		rINTRQ_S_CMD1 <= 1'b0;
		rINTRQ_S_FINT1 <= 1'b0;
	end
else
	begin
		rINTRQ_R_CMD1 <= rINTRQ_R_CMD;
		rINTRQ_S_CMD1 <= rINTRQ_S_CMD;
		rINTRQ_S_FINT1 <= rINTRQ_S_FINT;
		if ( rINTRQ_S_FINT1 != rINTRQ_S_FINT || rINTRQ_S_CMD1 != rINTRQ_S_CMD )
			rINTRQ <= 1'b1;
		else
			//if ( ( rRESETn1 | rRESETn2 ) == 1'b0 || r2RQ_R_SREG == 1'b1 || rINTRQ_R_CMD1 != rINTRQ_R_CMD )
			if ( r2RQ_R_SREG == 1'b1 || rINTRQ_R_CMD1 != rINTRQ_R_CMD )
				rINTRQ <= 1'b0;
			else
				if ( rINTRQ_S_CMD1 != rINTRQ_S_CMD )	rINTRQ <= 1'b1;
	end
//
always @( posedge iCLK )
if ( ( rRESETn1 | rRESETn2 ) == 1'b0 )
	begin
		rREG_TRK <= 8'b0;
		rREG_SEC <= 8'b1;
		rREG_DAT <= 8'b0;
		rREG_SHF <= 8'b0;
		rREG_CMD <= 8'd3;
		rDIRC <= 1'b0;
		rHLD <= 1'b0;
		rSTAGE <= 6'b0;
		rBUSY <= 1'b0;
		rLOST_DATA <= 1'b0;
		rCRC_ERROR <= 1'b0;
		rSEEK_ERROR <= 1'b0;
		rREC_NOT_FOUND <= 1'b0;
		rWRITE_FAULT <= 1'b0;
		rREC_TYPE <= 1'b0;
		rSTEP_SET <= 1'b0;
		rDELAY_SET <= 1'b0;
		rCURR_STATE <= TYPE1;
		rLAST_CURR_STATE <= TYPE1;
		oRESET_CRC <= 1'b0;
		rHEAD_IN_POS <= 1'b0;
		oWG <= 1'b0;
		rINTRQ_R_CMD <= 1'b0;
		rINTRQ_S_CMD <= 1'b0;
		rINTRQ_S_FINT <= 1'b0;
	end
else
	if ( ( rWR_EN & rWR_EN0 ) == 1'b1 )
		case ( iADR )
			2'b00:	begin
						rREG_CMD <= iDATA;
						if ( iDATA[7] == 1'b0 )
							begin
								rCURR_STATE <= TYPE1;	// 0xxx_xxxx 
								rLAST_CURR_STATE <= TYPE1;
							end
						else
							if ( iDATA[6] == 1'b0 )
								begin
									rCURR_STATE <= TYPE2;	// 10xx_xxxx  - , 
									rLAST_CURR_STATE <= TYPE2;
								end
							else
								if ( iDATA[4] == 1'b0 )
									begin
										rCURR_STATE <= TYPE3RD;	// 11x0_xxxx   , 
										rLAST_CURR_STATE <= TYPE3RD;
									end
								else
									if ( iDATA[5] == 1'b0 )
										begin
											rCURR_STATE <= FRC_INT;	// 1101_xxxx 
											rLAST_CURR_STATE <= FRC_INT;
										end
									else
										begin
											rCURR_STATE <= TYPE3WR;	// 1111_xxxx  
											rLAST_CURR_STATE <= TYPE3WR;
										end
//						casez ( iDATA[7:4] )
//							4'b0???:	rCURR_STATE <= TYPE1;
//							4'b10??:	rCURR_STATE <= TYPE2;
//							4'b11?0:	rCURR_STATE <= TYPE3RD;
//							4'b1111:	rCURR_STATE <= TYPE3WR;
//							4'b1101:	rCURR_STATE <= FRC_INT;
//						endcase
						rSTAGE <= 6'b0;
					end
			2'b01:	rREG_TRK <= iDATA;
			2'b10:	rREG_SEC <= iDATA;
			2'b11:	rREG_DAT <= iDATA;
		endcase
	else
		case ( rCURR_STATE )
			IDLE:	begin
						if ( rHLD == 1'b1 && rIP_CNT_IDLE == 4'b1111 )	rHLD <= 1'b0;
						rHEAD_IN_POS <= 1'b0;
					end
			TYPE1:	case ( rSTAGE )
						0:	begin
								rBUSY <= 1'b1;	//  
								rDRQ_R_CMD <= 1'b1;	//  DRQ
								rINTRQ_R_CMD <= ~rINTRQ_R_CMD;	//  INTRQ
								rSTAGE <= rSTAGE + 1'b1;
							end
						1:	begin
								rDRQ_R_CMD <= 1'b0;
								rHLD <= rREG_CMD[3];
								rSTAGE <= rSTAGE + 1'b1;
							end
						2:	if ( rREG_CMD[6] == 1'b1 )	//     
								begin
									rDIRC <= ~rREG_CMD[5];
									rSTAGE <= 31;
								end
							else
								rSTAGE <= rSTAGE + 1'b1;
						3:	if ( rREG_CMD[7:5] == 3'b001 )	// 
								rSTAGE <= 31;
							else
								rSTAGE <= rSTAGE + 1'b1;
						4:	if ( rREG_CMD[7:4] == 4'b0001 )	// 
								rSTAGE <= 6;
							else
								rSTAGE <= rSTAGE + 1'b1;
						5:	begin
								rREG_TRK <= 8'hFF;
								rREG_DAT <= 8'b0;
								rSTAGE <= rSTAGE + 1'b1;
							end
						6:	begin
								rREG_SHF <= rREG_DAT;
								rSTAGE <= rSTAGE + 1'b1;
							end
						7:	if ( rREG_TRK == rREG_SHF )
								rSTAGE <= 16;
							else
								rSTAGE <= rSTAGE + 1'b1;
						8:	begin
								rDIRC <= rREG_TRK < rREG_SHF;
								//rSTAGE <= rSTAGE + 1'b1;
								rSTAGE <=  32;
							end
						9: 	begin
								if ( rDIRC == 1'b1 )
									rREG_TRK <= rREG_TRK + 1'b1;
								else
									rREG_TRK <= rREG_TRK - 1'b1;
								rSTAGE <= rSTAGE + 1'b1;
							end
						10: if ( rTR002 == 1'b1 && rDIRC == 1'b0 )	// 
								begin
									rREG_TRK <= 8'b0;
									rSTAGE <= 16;
								end
							else
								rSTAGE <= rSTAGE + 1'b1;
						11: begin
								rSTEP_SET <= ~rSTEP_SET;
								rSTAGE <= rSTAGE + 1'b1;
							end
						12: if ( rSTEP_CNT == 4'd1 )
								rSTAGE <= rSTAGE + 1'b1;
						13: begin
								rDELAY_SET <= ~rDELAY_SET;
								case ( rREG_CMD[1:0] )
									2'b00:	rCNT_AMNT <= DELAY6;
									2'b01:	rCNT_AMNT <= DELAY12;
									2'b10:	rCNT_AMNT <= DELAY20;
									default:	rCNT_AMNT <= DELAY30;
								endcase
								rSTAGE <= rSTAGE + 1'b1;
							end
						14: if ( rDELAY_CNT == 8'd1 )
								rSTAGE <= rSTAGE + 1'b1;
						15: if ( rREG_CMD[7:5] != 3'b000 )	//    
								rSTAGE <= rSTAGE + 1'b1;
							else
								rSTAGE <= 6;
						16: if ( rREG_CMD[2] != 1'b1 )	// v != 1
								begin
									rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
									rSTAGE <= 30;
								end
							else
								rSTAGE <= rSTAGE + 1'b1;
						17: begin
								rHLD <= 1'b1;
								rSTAGE <= rSTAGE + 1'b1;
							end
						18: begin
								rCNT_AMNT <= DELAY30;	// 30       
								rDELAY_SET <= ~rDELAY_SET;
								rSTAGE <= rSTAGE + 1'b1;
							end
						19: if ( rDELAY_CNT == 0 )
								begin
									rSTAGE <= rSTAGE + 1'b1;
									rHEAD_IN_POS <= 1'b1;
								end
						20: if ( oIP_CNT == 9 )
								begin
									rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
									rSEEK_ERROR <= 1'b1;
									rSTAGE <= 30;
								end
							else
								rSTAGE <= rSTAGE + 1'b1;
						21:	if ( iSYNC == 1'b1 )
								begin
									oRESET_CRC <= 1'b1;
									rSTAGE <= rSTAGE + 1'b1;
								end
							else
								rSTAGE <= 20;
						22:	begin
								oRESET_CRC <= 1'b0;
								if ( iBYTE_CNT == 11'd4 )
									if ( iCRC16_D8 == 16'hB230 )	// A1,A1,A1,FE - 
										rSTAGE <= rSTAGE + 1'b1;
									else
										rSTAGE <= 20;
							end
						23:	if ( iBYTE_2_READ == 1'b1 )
								if ( rREG_TRK == iBYTE_2_MAIN )	//   
									rSTAGE <= rSTAGE + 1'b1;
								else
									rSTAGE <= 20;
						24:	if ( iBYTE_2_READ == 1'b1 )	rSTAGE <= rSTAGE + 1'b1;	//   
						25:	if ( iBYTE_2_READ == 1'b1 )	rSTAGE <= rSTAGE + 1'b1;	//   
						26:	if ( iBYTE_2_READ == 1'b1 )	rSTAGE <= rSTAGE + 1'b1;	//    
						27:	begin
								rSAVED_CRC <= iCRC16_D8;
								rSTAGE <= rSTAGE + 1'b1;
							end
						28:	if ( iBYTE_2_READ == 1'b1 )	//    
								begin
									rREAD_H_CRC <= iBYTE_2_MAIN;
									rSTAGE <= rSTAGE + 1'b1;
								end
						29:	if ( iBYTE_2_READ == 1'b1 )	//  ,    
								if ( rSAVED_CRC == { rREAD_H_CRC, iBYTE_2_MAIN } )
									begin
										rCRC_ERROR <= 1'b0;
										rSEEK_ERROR <= 1'b0;
										rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
										rSTAGE <= rSTAGE + 1'b1;
									end
								else
									begin
										rCRC_ERROR <= 1'b1;
										rSTAGE <= 20;
									end
						30:	begin
								rBUSY <= 1'b0;
								rCURR_STATE <= IDLE;
							end
						31: begin
								if ( rREG_CMD[4] == 1'b1 )
									rSTAGE <= 9;
								else
									rSTAGE <= 10;
							end
						//
						32: begin
								rDELAY_SET <= ~rDELAY_SET;
								rCNT_AMNT <= 3;
								rSTAGE <= rSTAGE + 1'b1;
							end
						33: if ( rDELAY_CNT == 8'd1 )	rSTAGE <= 9;
						//
						default:	rCURR_STATE <= IDLE;
					endcase
			TYPE2:	case ( rSTAGE )
						0:	begin
								rBUSY <= 1'b1;					//  
								rDRQ_R_CMD <= 1'b1;				//  DRQ
								rINTRQ_R_CMD <= ~rINTRQ_R_CMD;	//  INTRQ
								rLOST_DATA <= 1'b0;				//   
								rREC_NOT_FOUND <= 1'b0;			//    
								rWRITE_FAULT <= 1'b0;			//   
								rSTAGE <= rSTAGE + 1'b1;
							end
						1:	begin
								rDRQ_R_CMD <= 1'b0;
								if ( wCPRDY == 1'b1 )
									begin
										rHLD <= 1'b1;
										rHEAD_IN_POS <= 1'b1;
										rSTAGE <= rSTAGE + 1'b1;
									end
								else
									begin
										rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
										rSTAGE <= 60;
									end
							end
						2:	if ( rREG_CMD[2] == 1'b1 )	// E==1
								begin
									rDELAY_SET <= ~rDELAY_SET;
									rCNT_AMNT <= DELAY30;
									rSTAGE <= rSTAGE + 1'b1;
								end
							else
								rSTAGE <= 5;
						3:	rSTAGE <= rSTAGE + 1'b1;
						4:	if ( rDELAY_CNT == 8'd1 )
								rSTAGE <= rSTAGE + 1'b1;
						5:	if ( rREG_CMD[5] == 1'b0 )	//  ?
								rSTAGE <= 7;
							else
								rSTAGE <= rSTAGE + 1'b1;
						6:	if ( rWRPT2 == 1'b1 )	// WPRT 
								begin
									rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
									rSTAGE <= 60;
								end
							else
								rSTAGE <= rSTAGE + 1'b1;
						7:	if ( oIP_CNT >= 5 )
								begin
									rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
									rREC_NOT_FOUND <= 1'b1;
									rSTAGE <= 60;
								end
							else
								rSTAGE <= rSTAGE + 1'b1;
						8:	if ( iSYNC == 1'b1 )
								begin
									oRESET_CRC <= 1'b1;
									rSTAGE <= rSTAGE + 1'b1;
								end
							else
								rSTAGE <= 7;
						9:	begin
								oRESET_CRC <= 1'b0;
								if ( iBYTE_CNT == 11'd4 )
									if ( iCRC16_D8 == 16'hB230 )	// A1,A1,A1,FE - 
										rSTAGE <= rSTAGE + 1'b1;
									else
										rSTAGE <= 7;
							end
						10:	if ( iBYTE_2_READ == 1'b1 )
								if ( rREG_TRK == iBYTE_2_MAIN )	//   
									rSTAGE <= rSTAGE + 1'b1;
								else
									rSTAGE <= 7;
						11:	if ( iBYTE_2_READ == 1'b1 )
								if ( ( rREG_CMD[3] == iBYTE_2_MAIN[0] ) || ( rREG_CMD[1] == 1'b0 ) )	//       (C==0)
									rSTAGE <= rSTAGE + 1'b1;
								else
									rSTAGE <= 7;									
						12:	if ( iBYTE_2_READ == 1'b1 )
								if ( rREG_SEC == iBYTE_2_MAIN )	//   
									rSTAGE <= rSTAGE + 1'b1;
								else
									rSTAGE <= 7;
						13:	if ( iBYTE_2_READ == 1'b1 )
								begin
									case ( iBYTE_2_MAIN[1:0] )
										2'b00:	rSEC_LEN <= 11'd128;
										2'b01:	rSEC_LEN <= 11'd256;
										2'b10:	rSEC_LEN <= 11'd512;
										default:	rSEC_LEN <= 11'd1024;
									endcase
									rSTAGE <= rSTAGE + 1'b1;
								end
						14:	begin
								rSAVED_CRC <= iCRC16_D8;
								rSTAGE <= rSTAGE + 1'b1;
							end
						15:	if ( iBYTE_2_READ == 1'b1 )	//    
								begin
									rREAD_H_CRC <= iBYTE_2_MAIN;
									rSTAGE <= rSTAGE + 1'b1;
								end
						16:	if ( iBYTE_2_READ == 1'b1 )	//  ,    
								if ( rSAVED_CRC == { rREAD_H_CRC, iBYTE_2_MAIN } )
									begin
										rCRC_ERROR <= 1'b0;
										rSTAGE <= rSTAGE + 1'b1;
									end
								else
									begin
										rCRC_ERROR <= 1'b1;
										rSTAGE <= 7;
									end
						17:	if ( rREG_CMD[5] == 1'b0 )	//  ()
								rSTAGE <= rSTAGE + 1'b1;
							else
								rSTAGE <= 29;	//   
						18:	if ( iSYNC == 1'b1 )
								begin
									oRESET_CRC <= 1'b1;
									rSTAGE <= rSTAGE + 1'b1;
								end
						19:	begin
								oRESET_CRC <= 1'b0;
								if ( iCRC16_D8 == 16'hE295 )	// A1,A1,A1,FB - D
									begin
										rREC_TYPE <= 1'b0;
										rSTAGE <= rSTAGE + 1'b1;
									end
								else
									if ( iCRC16_D8 == 16'hD2F6 )	// A1,A1,A1,F8 - D deleted type
										begin
											rREC_TYPE <= 1'b1;
											rSTAGE <= rSTAGE + 1'b1;
										end
									else
										if ( oIP_CNT >= 5 )	rSTAGE <= 7;
							end
						20:	if ( iBYTE_2_READ == 1'b1 )
								begin
									if ( rDRQ == 1'b1 )
										rLOST_DATA <= 1'b1;
									else
										rDRQ_S_CMD <= 1'b1;
									rREG_DAT <= iBYTE_2_MAIN;
									rSTAGE <= rSTAGE + 1'b1;
								end
						21:	begin
								rDRQ_S_CMD <= 1'b0;
								rSTAGE <= rSTAGE + 1'b1;
							end
						22:	begin
								rSEC_LEN <= rSEC_LEN - 1'b1;
								rSTAGE <= rSTAGE + 1'b1;
							end
						23:	if ( rSEC_LEN == 11'b0 )
								rSTAGE <= rSTAGE + 1'b1;
							else	
								rSTAGE <= 20;
						24:	begin
								rSAVED_CRC <= iCRC16_D8;
								rSTAGE <= rSTAGE + 1'b1;
							end
						25:	if ( iBYTE_2_READ == 1'b1 )	//    
								begin
									rREAD_H_CRC <= iBYTE_2_MAIN;
									rSTAGE <= rSTAGE + 1'b1;
								end
						26:	if ( iBYTE_2_READ == 1'b1 )	//  ,    
								if ( rSAVED_CRC == { rREAD_H_CRC, iBYTE_2_MAIN } )
									begin
										rCRC_ERROR <= 1'b0;
										rSTAGE <= rSTAGE + 1'b1;
									end
								else
									begin
										rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
										rCRC_ERROR <= 1'b1;
										rSTAGE <= 60;
									end
						27:	if ( rREG_CMD[4] == 1'b1 )	// M==1  
								rSTAGE <= rSTAGE + 1'b1;
							else
								begin
									rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
									rSTAGE <= 60;
								end
						28:	begin
								rREG_SEC <= rREG_SEC + 1'b1;
								rSTAGE <= 5;
							end
						29:	begin	//  
								rDRQ_S_CMD <= 1'b1;
								rSTAGE <= rSTAGE + 1'b1;
							end
						30:	begin
								rDRQ_S_CMD <= 1'b0;
								rSTAGE <= rSTAGE + 1'b1;
							end
						31:	if ( iBYTE_CNT == 10'd13 )
								rSTAGE <= rSTAGE + 1'b1;
						32:	begin
								if ( rDRQ != 1'b0 )
									begin
										rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
										rLOST_DATA <= 1'b1;
										rSTAGE <= 60;
									end
								else
									rSTAGE <= rSTAGE + 1'b1;
							end
						33:	begin
								if ( iBYTE_CNT == 10'd33 )
									rSTAGE <= rSTAGE + 1'b1;
							end
						34:	begin
								oMAIN_2_BYTE <= 8'b0;
								oTRANSLATE <= 1'b0;
								rSTAGE <= rSTAGE + 1'b1;
							end
						35:	begin
								oWG <= 1'b1;
								oRESET_CRC <= 1'b1;
								rSTAGE <= rSTAGE + 1'b1;
							end
						36:	begin
								oRESET_CRC <= 1'b0;
								oBYTE_2_WRITE <= 1'b1;	//    -  
								rSTAGE <= rSTAGE + 1'b1;
							end
						37:	begin
								oBYTE_2_WRITE <= 1'b0;
								rSTAGE <= rSTAGE + 1'b1;
							end
						38:	if ( iBYTE_CNT == 10'd12 )
								rSTAGE <= rSTAGE + 1'b1;
							else
								if ( iNEXT_BYTE == 1'b1 )
									rSTAGE <= 36;
						39:	begin
								oRESET_CRC  <= 1'b1;
								rSTAGE <= rSTAGE + 1'b1;
							end
						40:	begin
								oRESET_CRC  <= 1'b0;
								rSTAGE <= rSTAGE + 1'b1;
							end
						41:	begin
								if ( iNEXT_BYTE == 1'b1 )
									begin
										oMAIN_2_BYTE <= 8'hA1;
										oTRANSLATE <= 1'b1;
										oBYTE_2_WRITE <= 1'b1;
										rSTAGE <= rSTAGE + 1'b1;
									end
							end
						42:	begin
								oBYTE_2_WRITE <= 1'b0;
								if ( iBYTE_CNT == 10'd2 )
									rSTAGE <= rSTAGE + 1'b1;
								else
									rSTAGE <= 41;
							end
						43:	begin
								if ( iNEXT_BYTE == 1'b1 )
									begin
										if ( rREG_CMD[0] == 1'b0 )	// a0 == 0?
											oMAIN_2_BYTE <= 8'hFB;
										else
											oMAIN_2_BYTE <= 8'hF8;
										oTRANSLATE <= 1'b0;
										oBYTE_2_WRITE <= 1'b1;	// ^										
										rSTAGE <= rSTAGE + 1'b1;
									end
							end
						44:	begin
								oBYTE_2_WRITE <= 1'b0;	// v
								//rSTAGE <= rSTAGE + 1'b1;
								rSTAGE <= 48;
							end
						45:	begin
								rSTAGE <= rSTAGE + 1'b1;
							end
						46:	begin
								rSTAGE <= rSTAGE + 1'b1;
							end
						47:	begin
								rSTAGE <= rSTAGE + 1'b1;
							end
						48:	if ( iNEXT_BYTE == 1'b1 )
								begin
									oBYTE_2_WRITE <= 1'b1;	// ^
									oMAIN_2_BYTE <= rREG_DAT;
									rSEC_LEN <= rSEC_LEN - 1'b1;
									rSTAGE <= rSTAGE + 1'b1;
								end
						49:	begin
								oBYTE_2_WRITE <= 1'b0;	// v
								rDRQ_S_CMD <= 1'b1;	// ^ DRQ
								rSTAGE <= rSTAGE + 1'b1;
							end
						50:	begin
								rDRQ_S_CMD <= 1'b0;	// v DRQ
								rSTAGE <= rSTAGE + 1'b1;
							end
						51:	if ( iNEXT_BYTE == 1'b1 )
								begin
									oBYTE_2_WRITE <= 1'b1;
									if ( rDRQ == 1'b0 )
										oMAIN_2_BYTE <= rREG_DAT;
									else
										oMAIN_2_BYTE <= 8'b0;
									rSEC_LEN <= rSEC_LEN - 1'b1;
									rSTAGE <= rSTAGE + 1'b1;
								end
						52:	begin
								oBYTE_2_WRITE <= 1'b0;	// v
								if ( rSEC_LEN == 11'd0 )
									rSTAGE <= rSTAGE + 1'b1;
								else
									rSTAGE <= 49;
							end
						53:	if ( iNEXT_BYTE == 1'b1 )
								begin
									oBYTE_2_WRITE <= 1'b1;	// ^
									rSAVED_CRC <= iCRC16_D8;
									oMAIN_2_BYTE <= iCRC16_D8[15:8];
									rSTAGE <= rSTAGE + 1'b1;
								end
						54:	begin
								oBYTE_2_WRITE <= 1'b0;	// v
								rSTAGE <= rSTAGE + 1'b1;
							end
						55:	if ( iNEXT_BYTE == 1'b1 )
								begin
									oBYTE_2_WRITE <= 1'b1;	// ^
									oMAIN_2_BYTE <= rSAVED_CRC[7:0];
									rSTAGE <= rSTAGE + 1'b1;
								end
						56:	begin
								oBYTE_2_WRITE <= 1'b0;	// v
								rSTAGE <= rSTAGE + 1'b1;
							end
						57:	if ( iNEXT_BYTE == 1'b1 )
								begin
									oBYTE_2_WRITE <= 1'b1;	// ^
									oMAIN_2_BYTE <= 8'hFF;
									rSTAGE <= rSTAGE + 1'b1;
								end
						58:	begin
								oBYTE_2_WRITE <= 1'b0;	// v
								rSTAGE <= rSTAGE + 1'b1;
							end
						59:	if ( iNEXT_BYTE == 1'b1 )
								begin
									oWG <= 1'b0;
									rSTAGE <= 27;
								end
						60:	begin
								rBUSY <= 1'b0;
								rCURR_STATE <= IDLE;
							end
						default:	rCURR_STATE <= IDLE;
					endcase
			TYPE3RD:	case ( rSTAGE )
							0:	begin
									rBUSY <= 1'b1;					//  
									rDRQ_R_CMD <= 1'b1;				//  DRQ
									rINTRQ_R_CMD <= ~rINTRQ_R_CMD;	//  INTRQ
									rLOST_DATA <= 1'b0;				//   
									rREC_NOT_FOUND <= 1'b0;			//    
									rWRITE_FAULT <= 1'b0;			//   
									rSTAGE <= rSTAGE + 1'b1;
								end
							1:	begin
									rDRQ_R_CMD <= 1'b0;
									if ( wCPRDY == 1'b1 )
										begin
											rHLD <= 1'b1;
											rHEAD_IN_POS <= 1'b1;
											rSTAGE <= rSTAGE + 1'b1;
										end
									else
										begin
											rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
											rSTAGE <= 18;	// 
										end
								end
							2:	if ( rREG_CMD[2] == 1'b1 )	// E==1
									begin
										rDELAY_SET <= ~rDELAY_SET;
										rCNT_AMNT <= DELAY30;
										rSTAGE <= rSTAGE + 1'b1;
									end
								else
									rSTAGE <= 5;
							3:	rSTAGE <= rSTAGE + 1'b1;
							4:	if ( rDELAY_CNT == 8'd1 )
									rSTAGE <= rSTAGE + 1'b1;
							5:	if ( rREG_CMD[5] == 1'b1 )
									begin
										rIPTRG0 <= rIPTRG;
										rSTAGE <= 14;	//  
									end
								else
									rSTAGE <= rSTAGE + 1'b1;
							6:	if ( oIP_CNT >= 5 )	//  
									begin
										rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
										rREC_NOT_FOUND <= 1'b1;
										rSTAGE <= 18;	// 
									end
								else
									rSTAGE <= rSTAGE + 1'b1;
							7:	if ( iSYNC == 1'b1 )
									begin
										oRESET_CRC <= 1'b1;
										rSTAGE <= rSTAGE + 1'b1;
									end
								else
									rSTAGE <= 6;
							8:	begin
									oRESET_CRC <= 1'b0;
									if ( iBYTE_CNT == 11'd4 )
										if ( iCRC16_D8 == 16'hB230 )	// A1,A1,A1,FE - 
											rSTAGE <= rSTAGE + 1'b1;
										else
											rSTAGE <= 6;
								end
							9:	if ( iBYTE_2_READ == 1'b1 )
									begin
										if ( rDRQ == 1'b1 )
											rLOST_DATA <= 1'b1;
										else
											rDRQ_S_CMD <= 1'b1;
										rREG_DAT <= iBYTE_2_MAIN;
										rSTAGE <= rSTAGE + 1'b1;
									end
							10:	begin
									rDRQ_S_CMD <= 1'b0;
									rSTAGE <= rSTAGE + 1'b1;
								end
							11:	if ( iBYTE_CNT == 11'd10 )
									rSTAGE <= rSTAGE + 1'b1;
								else
									begin
										if ( iBYTE_CNT == 11'd8 )	//  2-   CRC
											rSAVED_CRC <= iCRC16_D8;
										else
											if ( iBYTE_CNT == 11'd9 )
												rREAD_H_CRC <= iBYTE_2_MAIN;
											else
												if ( iBYTE_CNT == 11'd5 )
													rREG_SEC <= iBYTE_2_MAIN;
										rSTAGE <= 9;
									end
							12:	begin
									rCRC_ERROR <= rSAVED_CRC != { rREAD_H_CRC, iBYTE_2_MAIN };
									rSTAGE <= rSTAGE + 1'b1;
								end
							13:	if ( iBYTE_2_READ == 1'b1 )	//     1 ,       
									begin
										rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
										rSTAGE <= 18;	// 
									end
							14: begin	//  
									if ( rIPTRG0 != rIPTRG )
										rSTAGE <= rSTAGE + 1'b1;
								end
							15:	if ( iBYTE_2_READ == 1'b1 )
									begin
										rSTAGE <= rSTAGE + 1'b1;
										if ( rDRQ != 1'b0 )
											rLOST_DATA <= 1'b1;
										else
											begin
												rREG_DAT <= iBYTE_2_MAIN;
												rDRQ_S_CMD <= 1'b1;
											end
									end
							16: begin
									rDRQ_S_CMD <= 1'b0;
									rSTAGE <= rSTAGE + 1'b1;
								end
							17:	begin
									if ( rIPTRG0 == rIPTRG )
										begin
											rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
											rSTAGE <= rSTAGE + 1'b1;	// 
										end
									else
										rSTAGE <= 15;
								end
							18:	begin
									rBUSY <= 1'b0;
									rCURR_STATE <= IDLE;
								end
								default:	rCURR_STATE <= IDLE;
						endcase
			TYPE3WR:	case ( rSTAGE )
							0:	begin
									rBUSY <= 1'b1;					//  
									rDRQ_R_CMD <= 1'b1;				//  DRQ
									rINTRQ_R_CMD <= ~rINTRQ_R_CMD;	//  INTRQ
									rLOST_DATA <= 1'b0;				//   
									rREC_NOT_FOUND <= 1'b0;			//    
									rWRITE_FAULT <= 1'b0;			//   
									rSTAGE <= rSTAGE + 1'b1;
								end
							1:	begin
									rDRQ_R_CMD <= 1'b0;
									if ( wCPRDY == 1'b1 )
										begin
											rHLD <= 1'b1;
											rHEAD_IN_POS <= 1'b1;
											rSTAGE <= rSTAGE + 1'b1;
										end
									else
										begin
											rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
											rSTAGE <= 16;	// 
										end
								end
							2:	if ( rREG_CMD[2] == 1'b1 )	// E==1
									begin
										rDELAY_SET <= ~rDELAY_SET;
										rCNT_AMNT <= DELAY30;
										rSTAGE <= rSTAGE + 1'b1;
									end
								else
									rSTAGE <= 5;
							3:	rSTAGE <= rSTAGE + 1'b1;
							4:	if ( rDELAY_CNT == 8'd1 )
									rSTAGE <= rSTAGE + 1'b1;
							5:	if ( rWRPT2 == 1'b1 )	// WPRT 
									begin
										rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
										rSTAGE <= 17;	// 
									end
								else
									rSTAGE <= rSTAGE + 1'b1;
							6:	begin
									rDRQ_S_CMD <= 1'b1;
									rDELAY_SET <= ~rDELAY_SET;
									rCNT_AMNT <= 8'd2;
									rSTAGE <= rSTAGE + 1'b1;
								end
							7: begin
									rDRQ_S_CMD <= 1'b0;
									rSTAGE <= rSTAGE + 1'b1;
								end
							8: if ( rPREDELAY_CNT == 11'b11000000000 )	//  3 																 
									rSTAGE <= rSTAGE + 1'b1;
							9:	if ( rDRQ != 1'b0 )
									begin
										rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
										rLOST_DATA <= 1'b1;
										rSTAGE <= 17;	// 
									end
								else
									begin
										rSTAGE <= rSTAGE + 1'b1;
										rIPTRG0 <= rIPTRG;
									end
							10:	begin
									if ( rIPTRG0 != rIPTRG )
										begin
											oWG <= 1'b1;
											rLAST_MAIN_2_BYTE <= 1'b0;
											oMAIN_2_BYTE <= rREG_DAT;
											oTRANSLATE <= 1'b0;
											rDRQ_S_CMD <= 1'b1;
											rSTAGE <= rSTAGE + 1'b1;
										end
								end
							11:	begin
									rDRQ_S_CMD <= 1'b0;
									rSTAGE <= 16;
								end
							12:	begin
									if ( ( rREG_DAT == 8'hF5 ) && ( rLAST_MAIN_2_BYTE == 1'b0 ) )	oRESET_CRC <= 1'b1;
									rDRQ_S_CMD <= 1'b0;
									rSTAGE <= rSTAGE + 1'b1;
								end
							13:	begin
									oRESET_CRC <= 1'b0;
									oBYTE_2_WRITE <= 1'b1;
									case ( rREG_DAT )
										8'hF5:	begin
													oMAIN_2_BYTE <= 8'hA1;
													rLAST_MAIN_2_BYTE <= 1'b1;
													oTRANSLATE <= 1'b1;
													rDRQ_S_CMD <= 1'b1;
													rSTAGE <= 16;
												end
										8'hF6:	begin
													oMAIN_2_BYTE <= 8'hC2;
													rLAST_MAIN_2_BYTE <= 1'b0;
													oTRANSLATE <= 1'b1;
													rDRQ_S_CMD <= 1'b1;
													rSTAGE <= 16;
												end
										8'hF7:	begin
													oMAIN_2_BYTE <= iCRC16_D8[15:8];
													rLAST_MAIN_2_BYTE <= 1'b0;
													rSAVED_CRC[7:0] <= iCRC16_D8[7:0];
													oTRANSLATE <= 1'b0;
													rSTAGE <= rSTAGE + 1'b1;
												end
										default:	begin
														oMAIN_2_BYTE <= rREG_DAT;
														rLAST_MAIN_2_BYTE <= 1'b0;
														oTRANSLATE <= 1'b0;
														rDRQ_S_CMD <= 1'b1;
														rSTAGE <= 16;
													end
									endcase
								end
							14: begin
									oBYTE_2_WRITE <= 1'b0;
									if ( iNEXT_BYTE == 1'b0 )	rSTAGE <= rSTAGE + 1'b1;
								end
							15:	begin
									if ( iNEXT_BYTE == 1'b1 )
										begin
											oMAIN_2_BYTE <= rSAVED_CRC[7:0];
											oTRANSLATE <= 1'b0;
											rDRQ_S_CMD <= 1'b1;
											oBYTE_2_WRITE <= 1'b1;
											rSTAGE <= rSTAGE + 1'b1;
										end
								end
							16: begin
									oBYTE_2_WRITE <= 1'b0;
									rDRQ_S_CMD <= 1'b0;
									rSTAGE <= rSTAGE + 1'b1;
								end
							17:	begin
									if ( rIPTRG0 == rIPTRG )
										begin
											rINTRQ_S_CMD <= ~rINTRQ_S_CMD;
											rSTAGE <= 19;	// 
										end
									else
										rSTAGE <= rSTAGE + 1'b1;
								end
							18:	if ( iNEXT_BYTE == 1'b1 )
									if ( rDRQ != 1'b0 )
										begin
											rLOST_DATA <= 1'b1;
											oMAIN_2_BYTE <= 8'b0;
											oTRANSLATE <= 1'b0;
											oBYTE_2_WRITE <= 1'b1;
											rSTAGE <= 16;
										end
									else
										rSTAGE <= 12;
							19:	begin
									oWG <= 1'b0;
									rBUSY <= 1'b0;
									rCURR_STATE <= IDLE;
								end
							default:	rCURR_STATE <= IDLE;
						endcase
			FRC_INT:	begin
							rBUSY <= 1'b0;
							if ( rREG_CMD[3:0] != 0 )
								rINTRQ_S_FINT <= ~rINTRQ_S_FINT;
							else
								rINTRQ_R_CMD <= ~rINTRQ_R_CMD;
							rCURR_STATE <= IDLE;
						end
			default:	rCURR_STATE <= IDLE;
		endcase
//
always @( iADR, REG_STA, rREG_TRK, rREG_SEC, rREG_DAT )
case ( iADR )
	2'b00:	rDATA_OUT <= REG_STA;
	2'b01:	rDATA_OUT <= rREG_TRK;
	2'b10:	rDATA_OUT <= rREG_SEC;
	2'b11:	rDATA_OUT <= rREG_DAT;
endcase
//
always @( rHRDY2, rLAST_CURR_STATE, rREG_CMD[5], rBUSY, wCPRDY, rIP2, rTR002, rCRC_ERROR, rSEEK_ERROR, rHLD, rWRPT2, rDRQ, rLOST_DATA, rREC_NOT_FOUND, rREC_TYPE, rWRITE_FAULT )
begin
	REG_STA[0] = rBUSY;
	REG_STA[7] = ~wCPRDY;
	case ( rLAST_CURR_STATE )
		TYPE1:	begin
					REG_STA[1] = ~rIP2;
					REG_STA[2] = rTR002;
					REG_STA[3] = rCRC_ERROR;
					REG_STA[4] = rSEEK_ERROR;
					REG_STA[5] = rHLD & rHRDY2;
					REG_STA[6] = rWRPT2;
				end
		TYPE2:	begin
					REG_STA[1] = rDRQ;
					REG_STA[2] = rLOST_DATA;
					REG_STA[3] = rCRC_ERROR;
					REG_STA[4] = rREC_NOT_FOUND;
					if ( rREG_CMD[5] == 0 )
						begin	// read sector
							REG_STA[5] = rREC_TYPE;
							REG_STA[6] = 1'b0;
						end
					else
						begin	// write sector
							REG_STA[5] = rWRITE_FAULT;
							REG_STA[6] = rWRPT2;
						end
				end
		TYPE3RD:	begin
						REG_STA[1] = rDRQ;
						REG_STA[2] = rLOST_DATA;
						if ( rREG_CMD[5] == 0 )
							begin	// read address
								REG_STA[3] = rCRC_ERROR;
								REG_STA[4] = rREC_NOT_FOUND;
							end
						else
							begin	// read track
								REG_STA[3] = 1'b0;
								REG_STA[4] = 1'b0;
							end
						REG_STA[5] = 1'b0;
						REG_STA[6] = 1'b0;
					end
		TYPE3WR:	begin
						REG_STA[1] = rDRQ;
						REG_STA[2] = rLOST_DATA;
						REG_STA[3] = 1'b0;
						REG_STA[4] = 1'b0;
						REG_STA[5] = rWRITE_FAULT;
						REG_STA[6] = rWRPT2;
					end
		default:	begin
						REG_STA[1] = ~rIP2;
						REG_STA[2] = rTR002;
						REG_STA[3] = rCRC_ERROR;
						REG_STA[4] = rSEEK_ERROR;
						REG_STA[5] = rHLD & rHRDY2;
						REG_STA[6] = rWRPT2;
					end
	endcase
end
//
assign wCPRDY = 1'b1;
assign oDATA = rDATA_OUT;
assign oSTEP = rSTEP_CNT > 0;
assign oDIRC = rDIRC;
assign oHLD = rHLD;
assign oDRQ = rDRQ;
assign oINTRQ = rINTRQ;
assign oVFOE = ~( rHLD & rHRDY2 & rHEAD_IN_POS & ~oWG );
//
endmodule
