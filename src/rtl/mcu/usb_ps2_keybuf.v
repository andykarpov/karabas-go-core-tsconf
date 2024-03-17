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

 Antonio Sánchez (@TheSonders)
 
 Modified by Andy Karpov to accept parsed usb reports, convert them to ps/2 scancode sequences 
 and return them as sequences to the RTC registers 0xf0 - 0xff while reading using internal FIFO
*/
///////////////////////////////////////////////////////////////////////////

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

////////////////////////////////////////////////////////////
//                    PS2 CONVERSION                      //
//////////////////////////////////////////////////////////// 

reg PS2Busy=0;
reg [7:0]Cpy_Rmodifiers=8'h00;
reg [5:0]PS2_STM=0;
reg [7:0]Rmodifiers=0;
reg [7:0]PrevRmodifiers=0;
reg [47:0]RollOver=0;
reg [47:0]PrevRollOver=0;
reg [47:0]Cpy_RollOver=0;
reg AddKey=0;
reg SendKey=0;

reg [7:0] keybuf_di, keybuf_do;
reg keybuf_wr=0;
wire keybuf_full;
wire keybuf_empty;
wire [10:0] keybuf_data_count;
reg [2:0] keybuf_fsm = 0;
reg [23:0] keybuf_wr_data;

// keybuf fifo
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

////////////////////////////////////////////////////////////
//              FILL HID REPORT TO PROCESS                //
////////////////////////////////////////////////////////////
	 
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
	if (PS2Busy==1 && keybuf_fsm==0) begin
		case (PS2_STM)
			 // 8 modifiers (alt, ctrl, shift, meta)
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
			 // normal keys (up to 6 keys from hid report)
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

////////////////////////////////////////////////////////////
//                    KEYBUF FIFO SEQUENCER               //
////////////////////////////////////////////////////////////  
    case (keybuf_fsm) 
		  // idle state
        0: begin 
            keybuf_wr <= 0;
            keybuf_di <= 8'h00;
				// anti-underflow
				if (keybuf_data_count < 3) begin
					keybuf_wr <= 1;
				end
        end
		  // send 3 bytes sequence
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
		keybuf_fsm <= 1;
		keybuf_wr_data <= sig;
    end
endtask

endmodule

