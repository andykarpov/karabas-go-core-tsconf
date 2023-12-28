// IanPo/zx-pk.ru, 2017
// Модуль кодера MFM и записи для HDL-модели КР1818ВГ93/WD1793
//
`default_nettype none
//
module MFMCDR (
input				iCLK,			// тактовая 16 МГц
input				iRESETn,		// сброс ( пока не используется !!! )
input				iWG,			// WRITE GATE
input	[7:0]		iMAIN_2_BYTE,	// следущий байт
input				iBYTE_2_WRITE,	// следующий байт подан
input				iTRANSLATE,		// флаг трансляции байта ( для C2, A1 )
output	reg			oNEXT_BYTE,		// грузите следующий байт
output	reg			oWDATA
);
//
reg		[2:0]		rBIT_CNT;	// счетчик бит даных
reg		[1:0]		rMFM_BIT;	// 2 бита MFM, полученные из 1 бита данных
reg		[5:0]		rWDATA_CNT, rWDATA_CNT_MAX;	// счетчик 2-мкс интервалов
reg					rMFM_CNT;	// счетчик битов ( 2 бита MFM )
wire				wMFM_MSK;	// маска для кодирования C2, A1
reg		[2:0]		rLASTBITS;	// для выработки сигналов Late, Early
reg		[7:0]		rMAIN_2_BYTE;
//
parameter
	TWO_mks	= 6'd31,			//  2-мкс интервал (32 такта 16 МГц)
	HLF_mks	= 6'd8,				// 500 нс - ширина импульса
	NXT_byt = HLF_mks + 6'd2;	// положение флага NEXT_BYTE относительно импульса
//
initial
	begin
		oWDATA 			= 1'b0;
		rBIT_CNT		= 3'd7;
		oNEXT_BYTE		= 1'b0;
		rLASTBITS		= 3'b010;	// чтобы rWDATA_CNT_MAX = TWO_mks
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
