`timescale 1ns / 1ps

module rom (
    input wire clk,
    input wire [15:0] a,
    output reg [7:0] dout,
	 
	 input wire loader_act,
	 input wire [15:0] loader_a,
	 input wire [7:0] loader_d,
	 input wire loader_wr
    );

   reg [7:0] mem[0:65535];
   /*initial begin
      $readmemh ("ts-bios.hex", mem, 0);
   end*/

   always @(posedge clk) begin
		if (loader_act & loader_wr) begin
			mem[loader_a[15:0]] <= loader_d[7:0];
		end
     dout <= mem[a[15:0]];
   end
endmodule
