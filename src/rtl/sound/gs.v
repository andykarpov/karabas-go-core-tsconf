`default_nettype none
/*

  -----------------------------------------------------------------------------
   General Sound
  -----------------------------------------------------------------------------
   18.08.2018	Reworked first verilog version
   19.08.2018	Produce proper signed output
   20.08.2018	Use external SDR/DDR RAM for page 2 and up
   21.05.2020	Use external SDR/DDR RAM for all ROM/RAM

   CPU: Z80 @ 28MHz
   ROM: 32K
   RAM: up to 4096KB
   INT: 37.5KHz

   #xxBB Command register - регистр команд, доступный для записи
   #xxBB Status register - регистр состояния, доступный для чтения
  		bit 7 флаг данных
  		bit <6:1> Не определен
  		bit 0 флаг команд. Этот регистр позволяет определить состояние GS, в частности можно ли прочитать или записать очередной байт данных, или подать очередную команду, и т.п.
   #xxB3 Data register - регистр данных, доступный для записи. В этот регистр Спектрум записывает данные, например, это могут быть аргументы команд.
   #xxB3 Output register - регистр вывода, доступный для чтения. Из этого регистра Спектрум читает данные, идущие от GS
  
   Внутренние порта:
   #xx00 "расширенная память" - регистр доступный для записи
  		bit <3:0> переключают страницы по 32Kb, страница 0 - ПЗУ
  		bit <7:0> не используются
  
   порты 1 - 5 "обеспечивают связь с SPECTRUM'ом"
   #xx01 чтение команды General Sound'ом
  		bit <7:0> код команды
   #xx02 чтение данных General Sound'ом
  		bit <7:0> данные
   #xx03 запись данных General Sound'ом для SPECTRUM'a
  		bit <7:0> данные
   #xx04 чтение слова состояния General Sound'ом
  		bit 0 флаг команд
  		bit 7 флаг данных
   #xx05 сбрасывает бит D0 (флаг команд) слова состояния
  
   порты 6 - 9 "регулировка громкости" в каналах 1 - 4
   #xx06 "регулировка громкости" в канале 1
  		bit <5:0> громкость
  		bit <7:6> не используются
   #xx07 "регулировка громкости" в канале 2
  		bit <5:0> громкость
  		bit <7:6> не используются
   #xx08 "регулировка громкости" в канале 3
  		bit <5:0> громкость
  		bit <7:6> не используются
   #xx09 "регулировка громкости" в канале 4
  		bit <5:0> громкость
  		bit <7:6> не используются
  
   #xx0A устанавливает бит 7 слова состояния не равным биту 0 порта #xx00
   #xx0B устанавливает бит 0 слова состояния равным биту 5 порта #xx06
  
  Распределение памяти
  #0000 - #3FFF  -  первые 16Kb ПЗУ
  #4000 - #7FFF  -  первые 16Kb первой страницы ОЗУ
  #8000 - #FFFF  -  листаемые страницы по 32Kb
                    страница 0  - ПЗУ,
                    страница 1  - первая страница ОЗУ
                    страницы 2... ОЗУ
  
  Данные в каналы заносятся при чтении процессором ОЗУ по адресам  #6000 - #7FFF автоматически.

*/

module gs
(
	input wire        RESET,
	input wire        CLK,
	input wire        CE_N,
	input wire        CE_P,

	input wire        A,
	input wire  [7:0] DI,
	output wire [7:0] DO,
	input wire        CS_n, 
	input wire        WR_n,
	input wire        RD_n,

	output wire [20:0] MEM_ADDR,
	output wire [7:0] MEM_DI,
	input  wire [7:0] MEM_DO,
	output wire       MEM_RD,
	output wire       MEM_WR,
	input  wire       MEM_WAIT,

	output wire [14:0] OUTL,
	output wire [14:0] OUTR
);

parameter INT_DIV = 291;

// port #xxBB : #xxB3
assign DO = A ? {bit7, 6'b111111, bit0} : port_03;

// CPU
reg         int_n;
wire        cpu_m1_n;
wire        cpu_mreq_n;
wire        cpu_iorq_n;
wire        cpu_rfsh_n;
wire        cpu_rd_n;
wire        cpu_wr_n;
wire [15:0] cpu_a_bus;
wire  [7:0] cpu_do_bus;

T80pa cpu
(
	.RESET_n(~RESET),
	.CLK(CLK),
	.CEN_n(CE_N),
	.CEN_p(CE_P),
	.INT_n(int_n),
	.M1_n(cpu_m1_n),
	.MREQ_n(cpu_mreq_n),
	.RFSH_n(cpu_rfsh_n),
	.IORQ_n(cpu_iorq_n),
	.RD_n(cpu_rd_n),
	.WR_n(cpu_wr_n),
	.A(cpu_a_bus),
	.DO(cpu_do_bus),
	.DI(cpu_di_bus)
);

wire CE = CE_P;
reg [9:0] cnt;

// INT#
always @(posedge CLK) begin
	
	if (RESET) begin
		cnt <= 0;
		int_n <= 1;
	end else if(CE) begin
		cnt <= cnt + 1'b1;
		if (cnt == INT_DIV) begin // 37.48kHz
			cnt <= 0;
			int_n <= 0;
		end
	end

	if (~cpu_iorq_n & ~cpu_m1_n) int_n <= 1;
end


reg bit7;
reg bit0;
always @(posedge CLK) begin
	if (~cpu_iorq_n & cpu_m1_n) begin
		case(cpu_a_bus[3:0])
			'h2: bit7 <= 0;
			'h3: bit7 <= 1;
			'h5: bit0 <= 0;
			'hA: bit7 <= ~port_00[0];
			'hB: bit0 <=  port_09[5];
		endcase
	end
	else if (~CS_n) begin
		if (~A & ~RD_n) bit7 <= 0;
		if (~A & ~WR_n) bit7 <= 1;
		if ( A & ~WR_n) bit0 <= 1;
	end
end


reg [7:0] port_BB;
reg [7:0] port_B3;
always @(posedge CLK) begin
	if (RESET) begin
		port_BB <= 0;
		port_B3 <= 0;
	end
	else if (~CS_n && ~WR_n) begin
		if(A) port_BB <= DI;
		else  port_B3 <= DI;
	end
end

reg [5:0] port_00;
reg [7:0] port_03;
reg signed [6:0] port_06, port_07, port_08, port_09;
reg signed [7:0] ch_a, ch_b, ch_c, ch_d;

always @(posedge CLK) begin
	if (RESET) begin
		port_00 <= 0;
		port_03 <= 0;
	end
	else begin
		if (~cpu_iorq_n & ~cpu_wr_n) begin
			case(cpu_a_bus[3:0])
				0: port_00 <= cpu_do_bus[5:0];
				3: port_03 <= cpu_do_bus;
				6: port_06 <= cpu_do_bus[5:0];
				7: port_07 <= cpu_do_bus[5:0];
				8: port_08 <= cpu_do_bus[5:0];
				9: port_09 <= cpu_do_bus[5:0];
			endcase
		end

		if (mem_rd && cpu_a_bus[15:13] == 3 && ~MEM_WAIT) begin
			case(cpu_a_bus[9:8])
				0: ch_a <= {~MEM_DO[7],MEM_DO[6:0]};
				1: ch_b <= {~MEM_DO[7],MEM_DO[6:0]};
				2: ch_c <= {~MEM_DO[7],MEM_DO[6:0]};
				3: ch_d <= {~MEM_DO[7],MEM_DO[6:0]};
			endcase
		end
	end
end

wire [7:0] cpu_di_bus =
	mem_rd                                            ? MEM_DO  :
	(~cpu_iorq_n && ~cpu_rd_n && cpu_a_bus[3:0] == 1) ? port_BB :
	(~cpu_iorq_n && ~cpu_rd_n && cpu_a_bus[3:0] == 2) ? port_B3 :
	(~cpu_iorq_n && ~cpu_rd_n && cpu_a_bus[3:0] == 4) ? {bit7, 6'b111111, bit0} :
	8'hFF;

wire mem_wr = ~cpu_wr_n & ~cpu_mreq_n & |page_addr;
wire mem_rd = ~cpu_rd_n & ~cpu_mreq_n;

wire [5:0] page_addr = cpu_a_bus[15] ? port_00 : cpu_a_bus[14];

assign MEM_ADDR = {page_addr, &cpu_a_bus[15:14], cpu_a_bus[13:0]};
assign MEM_RD   = mem_rd;
assign MEM_WR   = mem_wr;
assign MEM_DI   = cpu_do_bus;

reg signed [14:0] out_a,out_b,out_c,out_d;
always @(posedge CLK) begin
	if(CE) begin
		out_a <= ch_a * port_06;
		out_b <= ch_b * port_07;
		out_c <= ch_c * port_08;
		out_d <= ch_d * port_09;
	end
end

reg signed [14:0] outl, outr;
always @(posedge CLK) begin
	if(CE) begin
		outl <= out_a + out_b;
		outr <= out_c + out_d;
	end
end

assign OUTL = outl;
assign OUTR = outr;

endmodule
