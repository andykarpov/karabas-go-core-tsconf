`include "tune.v"

module sram
(
  input  wire        clk,
  input  wire        cyc,
  input  wire        c0, c1, c2, c3,
  input  wire        req,    
  input  wire [20:0] addr,   
                             
                             
                             
  input  wire [15:0] wrdata, // data to be written
  input  wire [1:0]  bsel,   // positive byte select for write:
                             //   bsel[0] - wrdata[7:0]
                             //   bsel[1] - wrdata[15:8]
  input  wire        rnw,    // read/~write

// SRAM pins
  output reg [20:0]   sram_addr,
  inout      [15:0]   sram_data,
  output reg          sram_we_n,
  output reg          sram_ub_n,
  output reg          sram_lb_n,
  // data from sram
  output reg [15:0]   sram_do
);

reg [4:0] state;
reg [15:0] data;
reg [15:0] data_s;
reg [15:0] sram_dq;
reg [20:0] Areg;
reg sram_out;
reg rd;
reg rq;
reg [1:0] dqm;

  always @(posedge clk) 
  begin
	 data_s <= sram_data;
	 data <= data_s;
	 sram_out <= 1'b0;
	 state <= state+1;
    case (state)
	 // init
	 0: begin
	      sram_addr <= 0;
			sram_ub_n <= 1'b1;
			sram_lb_n <= 1'b1;
			sram_we_n <= 1'b1;
	    end
	  9: begin
 			 {sram_ub_n,sram_lb_n} <= 2'b00;
		  end
	 // idle
	 10: begin
			 if (rd) begin
				sram_do <= data;
			 end

			 state <= state;
			 Areg <= addr;
			 dqm <= rnw ? 2'b00 : ~bsel;
			 rd <= 0;

			 if(cyc) begin
				rq <= req;
				rd <= req & rnw;
				state <= state + 1'd1;
			 end	 
	     end
	 // begin	 
	 12: begin
			 if (rq) begin
				sram_addr <= Areg;
				{sram_ub_n,sram_lb_n} <= dqm;
			 end else begin
				state <= 10;
			 end
		  end 	 
    13: begin
			 if (rd) state <= 8;
			 else begin
				sram_out <= 1'b1;
				sram_dq <= wrdata;
				sram_we_n <= 1'b1;
				state <= 14;
			end			 
   	  end
	 14,15: 
	     begin
			 sram_out <= 1'b1;
			 sram_we_n <= 1'b0;
		  end
	 16: begin
			 sram_out <= 1'b1;
			 sram_we_n <= 1'b1;
			 state <= 9;
		  end    
	 endcase
  end

  assign sram_data = sram_out ? sram_dq : 16'hZZZZ;

endmodule
