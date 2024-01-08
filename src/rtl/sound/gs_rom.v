`timescale 1ns / 1ps

module gs_rom (
    input wire clk_gs,
	 input wire clk_bus,
    input wire [14:0] a,
    output reg [7:0] dout,
	 
	 input wire loader_act,
	 input wire [31:0] loader_a,
	 input wire [7:0] loader_d,
	 input wire loader_wr
    );

   reg [7:0] mem[0:32767];
   /*initial begin
      $readmemh ("gs.hex", mem, 0);
   end*/

   always @(posedge clk_bus) begin
		if (loader_act & loader_wr & loader_a[31]) begin
			mem[loader_a[14:0]] <= loader_d[7:0];
		end
	end

	always @(posedge clk_gs) begin
     dout <= mem[a[14:0]];
   end
endmodule
