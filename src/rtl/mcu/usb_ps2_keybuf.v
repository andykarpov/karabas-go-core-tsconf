///////////////////////////////////////////////////////////////////////////
/*
MIT License

Copyright (c) 2021 Antonio Sánchez (@TheSonders)
THE EXPERIMENT GROUP (@agnuca @Nabateo @subcriticalia)

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

 USB<->PS2
Convertidor de teclado USB a teclado PS2 con soporte de LEDs
Este módulo recibe y maneja directamente las líneas de transmisión USB.
Genera las señales PS/2 a 19200 baudios que simulan las teclas pulsadas/soltadas.
 
 USO DEL MÓDULO:
 -Señal de entrada de reloj 48MHz
 -Señales de entrada/Salida USB (D+ y D-)
 -Señales de salida PS/2 (CLK y DTA)
 -Señales de entrada del estado deseado para los 3 leds del teclado USB
    (Si no van a usarse estas entradas conectar a lógica 0)
 
 Antonio Sánchez (@TheSonders)
 Referencias:
 -Ben Eater Youtube Video:
     https://www.youtube.com/watch?v=wdgULBpRoXk
 -USB Specification Revision 2.0
 -https://usb.org/sites/default/files/hut1_22.pdf
 -https://crccalc.com/
 -https://www.perytech.com/USB-Enumeration.htm
 
 Modified by Andy Karpov to accept parsed usb reports, convert them to ps/2 scancode sequences 
 and return them as sequences to the RTC registers 0xf0 - 0xff while reading 
*/
///////////////////////////////////////////////////////////////////////////

//
`define LineAsInput     0
`define LineAsOutput    1

module usb_ps2_keybuf
    (input wire clk,
	 input wire reset,
	 input wire [7:0] kb_status,
	 input wire [7:0] kb_dat0,
	 input wire [7:0] kb_dat1,
	 input wire [7:0] kb_dat2,
	 input wire [7:0] kb_dat3,
	 input wire [7:0] kb_dat4,
	 input wire [7:0] kb_dat5,

	input wire keybuf_rd=0,
    input wire keybuf_reset=0,
	output wire [7:0] keybuf_data);

`define CLK_MULT        50000   //(CLK / 1000)
`define PS2_PRES        2499    //(CLK / 10000 baud / 2)-1
`define TYPEMATIC_DELAY 25000 // 25 // 25 000 000 (2 Hz) [23:0]
`define TYPEMATIC_CPS   5000  // 5  // 5 000 000 (10 Hz) [23:0]

////////////////////////////////////////////////////////////
//                    PS2 CONVERSION                      //
//////////////////////////////////////////////////////////// 
`define LEFT_CTRL   0
`define LEFT_SHIFT  1
`define LEFT_ALT    2
`define LEFT_GUI    3
`define RIGHT_CTRL  4
`define RIGHT_SHIFT 5
`define RIGHT_ALT   6
`define RIGHT_GUI   7
`define Release_Key 8'hF0
`define StopBit     1'b1
`define StartBit    1'b0
`define NextChar    PS2_signal[8:1]

reg PS2Busy=0;
reg [7:0]Cpy_Rmodifiers=8'h00;
reg [32:0]PS2_signal=0;
reg [6:0]PS2TX_STM=0;
reg [5:0]PS2_STM=0;
reg PS2_buffer_busy=0;
reg ParityBit=0;
reg [$clog2(`PS2_PRES)-1:0]PS2_Prescaler=0;
reg [7:0]Rmodifiers=0;
reg [7:0]PrevRmodifiers=0;
reg [47:0]RollOver=0;
reg [47:0]PrevRollOver=0;
reg [47:0]Cpy_RollOver=0;
reg AddKey=0;
reg SendKey=0;

reg PS2clock=1;
reg PS2data=1;

reg [7:0] keybuf_di, keybuf_do;
reg keybuf_wr=0;
wire keybuf_full;
wire keybuf_empty;
wire [10:0] keybuf_data_count;
reg [2:0] keybuf_fsm = 0;
reg [23:0] keybuf_wr_data;

fifo_keybuf u_keybuf (
	.clk(clk),
	.rst(keybuf_reset),
	.din(keybuf_di),
	.wr_en(keybuf_wr),
	.rd_en(keybuf_rd),
	.dout(keybuf_data),
	.full(keybuf_full),
	.empty(keybuf_empty),
	.data_count(keybuf_data_count)
);

always @(posedge clk)begin
    if (StartTimer==1) StartTimer<=0;
	 
	 if (PS2Busy == 0) begin
		 Rmodifiers <= kb_status;
		 RollOver <= {kb_dat5, kb_dat4, kb_dat3, kb_dat2, kb_dat1, kb_dat0};
		 if ((PrevRollOver != RollOver) || (PrevRmodifiers != Rmodifiers)) begin
			PrevRollOver <= RollOver;
			PrevRmodifiers <= Rmodifiers;
			PS2Busy <= 1;
		 end
	 end
    
////////////////////////////////////////////////////////////
//                    PS2 CONVERSION                      //
////////////////////////////////////////////////////////////
    if (PS2_buffer_busy==0)begin
        if (PS2Busy==1) begin
            case (PS2_STM)
                1,3,5,7,9,11,13,15: begin
                    PS2_STM<=PS2_STM+1;
                    Cpy_Rmodifiers<={Cpy_Rmodifiers[0],Cpy_Rmodifiers[7:1]};
                    Rmodifiers<={Rmodifiers[0],Rmodifiers[7:1]};
                end
                0: begin
                    PS2_STM<=PS2_STM+1;
                    if(Cpy_Rmodifiers[0]!=Rmodifiers[0])begin    
                        Cpy_Rmodifiers[0]<=Rmodifiers[0];
                        if (Cpy_Rmodifiers[0]==1) begin
                            Add_PS2_Buffer(24'h00F014);
                        end
                        else begin
                            Add_PS2_Buffer(24'h000014);
                        end
                    end
                end
                2: begin
                    PS2_STM<=PS2_STM+1;
                    if(Cpy_Rmodifiers[0]!=Rmodifiers[0])begin
                        Cpy_Rmodifiers[0]<=Rmodifiers[0];
                        if (Cpy_Rmodifiers[0]==1) begin
                            Add_PS2_Buffer(24'h00F012);
                        end
                        else begin
                            Add_PS2_Buffer(24'h000012);
                        end
                    end
                end
                4: begin
                    PS2_STM<=PS2_STM+1;
                    if(Cpy_Rmodifiers[0]!=Rmodifiers[0])begin
                        Cpy_Rmodifiers[0]<=Rmodifiers[0];
                        if (Cpy_Rmodifiers[0]==1) begin
                            Add_PS2_Buffer(24'h00F011);
                        end
                        else begin
                            Add_PS2_Buffer(24'h000011);
                        end
                    end
                end
                6: begin
                    PS2_STM<=PS2_STM+1;
                    if(Cpy_Rmodifiers[0]!=Rmodifiers[0])begin
                        Cpy_Rmodifiers[0]<=Rmodifiers[0];
                        if (Cpy_Rmodifiers[0]==1) begin
                            Add_PS2_Buffer(24'hE0F01F);
                        end
                        else begin
                            Add_PS2_Buffer(24'h00E01F);
                        end
                    end
                end
                8: begin
                    PS2_STM<=PS2_STM+1;
                    if(Cpy_Rmodifiers[0]!=Rmodifiers[0])begin
                        Cpy_Rmodifiers[0]<=Rmodifiers[0];
                        if (Cpy_Rmodifiers[0]==1) begin
                            Add_PS2_Buffer(24'hE0F014);
                        end
                        else begin
                            Add_PS2_Buffer(24'h00E014);
                        end
                    end
                end
                10: begin
                    PS2_STM<=PS2_STM+1;
                    if(Cpy_Rmodifiers[0]!=Rmodifiers[0])begin
                        Cpy_Rmodifiers[0]<=Rmodifiers[0];
                        if (Cpy_Rmodifiers[0]==1) begin
                            Add_PS2_Buffer(24'h00F059);
                        end
                        else begin
                            Add_PS2_Buffer(24'h000059);
                        end
                    end
                end
                12: begin
                    PS2_STM<=PS2_STM+1;
                    if(Cpy_Rmodifiers[0]!=Rmodifiers[0])begin
                        Cpy_Rmodifiers[0]<=Rmodifiers[0];
                        if (Cpy_Rmodifiers[0]==1) begin
                            Add_PS2_Buffer(24'hE0F011);
                        end
                        else begin
                            Add_PS2_Buffer(24'h00E011);
                        end
                    end
                end
                14: begin
                    PS2_STM<=PS2_STM+1;
                    if(Cpy_Rmodifiers[0]!=Rmodifiers[0])begin
                        Cpy_Rmodifiers[0]<=Rmodifiers[0];
                        if (Cpy_Rmodifiers[0]==1) begin
                            Add_PS2_Buffer(24'hE0F027);
                        end
                        else begin
                            Add_PS2_Buffer(24'h00E027);
                        end
                    end
                end
                17,20,23,26,29,32:begin PS2_STM<=PS2_STM+1;end //Wait for memory
                16,19,22,25,28,31:begin
                    PS2_STM<=PS2_STM+1;
                    if (Cpy_RollOver[7:0]!=RollOver[7:0])begin
                        SendKey<=1;
                        if (Cpy_RollOver[7:0]==0) begin// Add key
                            Cpy_RollOver[7:0]<=RollOver[7:0];
                            PS2MemoryAdd<=RollOver[7:0];
                            AddKey<=1;
                        end
                        else begin //Remove key
                            Cpy_RollOver<={8'h00,Cpy_RollOver[47:8]};
                            PS2MemoryAdd<=Cpy_RollOver[7:0];
                            AddKey<=0;
                        end
                    end
                    else SendKey<=0;
                end
                18,21,24,27,30,33:begin
                    PS2_STM<=PS2_STM+1;
                    Cpy_RollOver<={Cpy_RollOver[7:0],Cpy_RollOver[47:8]};
                    RollOver<={RollOver[7:0],RollOver[47:8]};
                    if (SendKey==1 && PS2Code[7:0]!=0)begin //Invalid keys
                    if (AddKey==1)begin
                        Add_PS2_Buffer({8'h0,PS2Code});
                    end
                    else begin
                        Add_PS2_Buffer({PS2Code[15:8],8'hF0,PS2Code[7:0]});
                    end
                    end
                end
                34: begin
                    PS2_STM<=0;
                    PS2Busy<=0;
                end
            endcase
         end
    end
////////////////////////////////////////////////////////////
//                    PS2 TRANSMISION                     //
////////////////////////////////////////////////////////////  
    else begin
        if (PS2_Prescaler==0) begin
        PS2_Prescaler<=`PS2_PRES;
        case(PS2TX_STM) 
            0,24: begin
                if (`NextChar==0) begin
                    PS2_signal<={11'b0,PS2_signal[32:11]};
                    PS2TX_STM<=PS2TX_STM+24;
                end
                else begin
                    ParityBit<=1;
                    PS2TX_STM<=PS2TX_STM+1;
                    PS2data<=`StartBit;
                end
            end
            48: begin
                if (`NextChar==0) begin
                    PS2_buffer_busy<=0;
                    PS2TX_STM<=0;
                end
                else begin
                    ParityBit<=1;
                    PS2TX_STM<=PS2TX_STM+1;
                    PS2data<=`StartBit;
                end
            end
            18,42,66: begin
                PS2clock<=1;
                PS2data<=ParityBit;
                PS2TX_STM<=PS2TX_STM+1;
            end
            23,47: PS2TX_STM<=PS2TX_STM+1;
            71: begin
                PS2_buffer_busy<=0;
                PS2TX_STM<=0;
            end
            default: begin
                if (PS2TX_STM[0]==0) begin
                    PS2clock<=1;
                    PS2data<=PS2_signal[0];
                    PS2TX_STM<=PS2TX_STM+1;
                end
                else begin
                    PS2clock<=0;
                    PS2_signal<={1'b0,PS2_signal[32:1]};
                    ParityBit<=ParityBit^PS2data;
                    PS2TX_STM<=PS2TX_STM+1;
                end
            end
        endcase
        end
        else PS2_Prescaler<=PS2_Prescaler-1;
    end 

////////////////////////////////////////////////////////////
//                    KEYBUF FIFO SEQUENCER               //
////////////////////////////////////////////////////////////  
    case (keybuf_fsm) 
        0: begin 
            keybuf_wr <= 0;
            keybuf_di <= 8'h00;
				// anti-underflow
				if (keybuf_data_count < 3) begin
					keybuf_wr <= 1;
				end
        end
        1: begin
            keybuf_wr <= 1;
            keybuf_di <= keybuf_wr_data[23:16];
            keybuf_fsm <= 2;
        end
        2: begin
            keybuf_wr <= 1;
            keybuf_di <= keybuf_wr_data[15:8];
            keybuf_fsm <= 3;
        end
        3: begin
            keybuf_wr <= 1;
            keybuf_di <= keybuf_wr_data[7:0];
            keybuf_fsm <= 0;
        end
    endcase
end

////////////////////////////////////////////////////////////
//                    PS2 MEMORY TABLE                    //
////////////////////////////////////////////////////////////  
reg [15:0]PS2Memory[0:127];
reg [6:0]PS2MemoryAdd=0;
reg [15:0]PS2Code=0;
initial 
	$readmemh ("usb_ps2_lut.txt",PS2Memory);
    
always @(posedge clk)begin
    PS2Code<=PS2Memory[PS2MemoryAdd];
end    

task Add_PS2_Buffer(input [23:0]sig);
    begin
    PS2_buffer_busy<=1;
    PS2_signal<=
        {`StopBit,`StopBit,sig[7:0],`StartBit,`StopBit,`StopBit,sig[15:8],`StartBit,`StopBit,`StopBit,sig[23:16],`StartBit};

    keybuf_fsm <= 1;
    keybuf_wr_data <= sig;

    end
endtask


////////////////////////////////////////////////////////////
//                Temporizador auxiliar                   //
//////////////////////////////////////////////////////////// 
reg [19:0] TimerPreload=0;
reg StartTimer=0;
wire TimerEnd;
Timer Timer(
    .clk(clk),
    .TimerPreload(TimerPreload),
    .StartTimer(StartTimer),
    .TimerEnd(TimerEnd));
task SetTimer(input integer milliseconds);
    begin
        TimerPreload<=`CLK_MULT*milliseconds;
        StartTimer<=1;
    end
endtask
endmodule

module Timer (
    input wire clk,
    input wire [19:0]TimerPreload,
    input wire StartTimer,
    output wire TimerEnd);
    
    assign TimerEnd=(rTimerEnd & ~StartTimer);
    
    reg rTimerEnd=0;
    reg PrevStartTimer=0;
    reg [19:0]Counter=0;
    always @(posedge clk)begin
        PrevStartTimer<=StartTimer;
        if (StartTimer && !PrevStartTimer)begin
            Counter<=TimerPreload;
            rTimerEnd<=0;
        end
        else if (Counter==0) begin
            rTimerEnd<=1;
        end
        else Counter<=Counter-1;
    end    
endmodule 
