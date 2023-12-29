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
  output wire [1:0]    sram_we_n,
  output wire [1:0]    sram_rd_n,
  // data from sram
  output reg [15:0]   sram_do
);

reg int_sram_ub_n;
reg int_sram_lb_n;
reg int_sram_we_n;

assign sram_we_n = (!int_sram_we_n ? {int_sram_ub_n, int_sram_lb_n} : 2'b11);
assign sram_rd_n = 2'b00; // int_sram_we_n ? 2'b00 : 2'b11;

reg [4:0] state;
reg [15:0] data;
reg [15:0] data_s;
reg [15:0] sram_dq;
reg [20:0] Areg;
reg sram_out;
reg rd;
reg rq;
reg [1:0] dqm;
reg [1:0] bsel_r;
reg bsel_addr;
reg bsel_xor;
reg [7:0] sram_low;

  always @(posedge clk) 
  begin
	 data <= sram_data;
	 //data <= data_s;
	 sram_out <= 1'b0;
	 state <= state+1;
    case (state)
	 // init
	 0: begin
	      sram_addr <= 0;
			int_sram_ub_n <= 1'b1;
			int_sram_lb_n <= 1'b1;
			int_sram_we_n <= 1'b1;
	    end
	  9: begin
 			 //{sram_ub_n,sram_lb_n} <= 2'b00;
		  end
	 // idle
	 10: begin
			if (rd) begin
			  if (Areg[20]) begin
  			    sram_do <= {data[15:8],sram_low};
			  end else begin 
			    sram_do <= {data[7:0],sram_low};
			  end
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
		 
	 11: begin
	       if (rq) begin
			     sram_addr[20:1] <= Areg[19:0];
				  int_sram_lb_n <= Areg[20];
				  int_sram_ub_n <= !Areg[20];
				  if (rd) begin
				    sram_addr[0] <= 1'b0;
				    state <= 12;
				  end else begin
                sram_addr[0] <= bsel_r[1] & !bsel_r[0];
			       bsel_addr <= bsel_r[1] & !bsel_r[0];
                bsel_xor <= bsel_r[1] ^ bsel_r[0];					 
				    state <= 15;
				  end	 
			 end else begin
			   state <= 10;
			 end
		  end
	 13: begin
	       sram_addr[0] <= 1'b1;
	     end
	 14: begin
			 if (Areg[20]) begin
			   sram_low <= data[15:8];
			 end else begin 
			   sram_low <= data[7:0];
			 end
			 state <= 9;
	     end
		  
	 15: begin
	       if (bsel_addr) begin
			   sram_dq <= {wrdata[15:8],wrdata[15:8]};
			 end else begin
			   sram_dq <= {wrdata[7:0],wrdata[7:0]};
			 end
			 sram_out <= 1'b1;
			 int_sram_we_n <= 1'b0;  			 
	     end

	 16: begin
			 sram_out <= 1'b0;
			 int_sram_we_n <= 1'b1;  			 
	     end

	 17: begin
	       if (bsel_xor) begin
			   state <= 10;
			 end else begin
  	          sram_addr[0] <= 1'b1;
				 state <= 18;
			 end
	     end

	 18: begin
  	       sram_dq <= {wrdata[15:8],wrdata[15:8]};
			 sram_out <= 1'b1;
			 int_sram_we_n <= 1'b0;  			 
	     end

	 19: begin
			 sram_out <= 1'b0;
			 int_sram_we_n <= 1'b1;  			 
			 state <= 10;
	     end
	
//	 10: begin
//			 if (rd) begin
//				sram_do <= data;
//			 end
//
//			 state <= state;
//			 Areg <= addr;
//			 dqm <= rnw ? 2'b00 : ~bsel;
//			 rd <= 0;
//
//			 if(cyc) begin
//				rq <= req;
//				rd <= req & rnw;
//				state <= state + 1'd1;
//			 end	 
//	     end
//	 // begin	 
//	 12: begin
//			 if (rq) begin
//				sram_addr <= Areg;
//				{sram_ub_n,sram_lb_n} <= dqm;
//			 end else begin
//				state <= 10;
//			 end
//		  end 	 
//    13: begin
//			 if (rd) state <= 8;
//			 else begin
//				sram_out <= 1'b1;
//				sram_dq <= wrdata;
//				sram_we_n <= 1'b1;
//				state <= 14;
//			end			 
//   	  end
//	 14,15: 
//	     begin
//			 sram_out <= 1'b1;
//			 sram_we_n <= 1'b0;
//		  end
//	 16: begin
//			 sram_out <= 1'b1;
//			 sram_we_n <= 1'b1;
//			 state <= 9;
//		  end    
	 endcase
  end

  assign sram_data = sram_out ? sram_dq : 16'hZZZZ;

endmodule
