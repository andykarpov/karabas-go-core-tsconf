`include "../../tune.v"

module sram
(
  input  wire        clk,
  input  wire        cyc,
  input  wire        c0, c1, c2, c3,

  // dram software interface
  input  wire        req,    
  input  wire [20:0] addr,                                
  input  wire [15:0] wrdata, // data to be written
  input  wire [1:0]  bsel,   // positive byte select for write:
                             //   bsel[0] - wrdata[7:0]
                             //   bsel[1] - wrdata[15:8]
  input  wire        rnw,    // read/~write

  // sram phy interface
  output reg [20:0]   sram_addr,
  inout      [15:0]   sram_data,
  output reg [1:0]    sram_we_n,
  output reg [1:0]    sram_rd_n,
  
  // data from sram
  output reg [15:0]   sram_do
);

reg [4:0] state;
reg [15:0] data;
reg [15:0] sram_dq;
reg [20:0] Areg;
reg sram_out;
reg rd;
reg rq;
reg [1:0] bsel_r;

  always @(posedge clk) 
  begin
	 data <= sram_data;
	 sram_out <= 1'b0;
	 state <= state+1;
    case (state)

	 // init
	 0: begin
	      sram_addr <= 0;
			sram_rd_n <= 2'b11;
			sram_we_n <= 2'b11;
	    end
		 
	  // disable read/write 	 
	  9: begin
		sram_rd_n <= 2'b11;
		sram_we_n <= 2'b11;
		  end 

	 // idle
	 10: begin
			if (rd) begin
				sram_do <= data;
		   end
			
			state <= state;
			Areg <= addr;
			rd <= 1'b0;
			
			if (cyc) begin
			  rq <= req;
			  rd <= req & rnw;
			  bsel_r <= bsel;
			  state <= state + 1'd1;
			end
		 end

	 // request
	 11: begin
	       if (rq) begin
			     sram_addr <= Areg;
				  if (rd) begin
					 sram_rd_n <= 2'b00;
				    state <= 12; // read
				  end else begin
				    state <= 15; // write
				  end	 
			 end else begin
			   state <= 10; // idle
			 end
		  end

	 // read continute to idle
	 13: begin
		state <= 9;
	     end
		  
	 // write set data
	 15: begin
			sram_dq <= wrdata;
			sram_out <= 1'b1;
			sram_we_n <= ~bsel_r;
	     end

	 // write end
	 16: begin
			 sram_out <= 1'b0;
			 sram_we_n <= 2'b11;
	     end

	 // goto idle
	 17: begin
		state <= 10;
		end
	endcase

  end

  assign sram_data = sram_out ? sram_dq : 16'hZZZZ;

endmodule
