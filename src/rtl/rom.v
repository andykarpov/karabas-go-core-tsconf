`timescale 1ns / 1ps

module rom (
    input wire clk,
    input wire [15:0] a,
    output reg [7:0] dout
    );

   reg [7:0] mem[0:65535];
   initial begin
      $readmemh ("ts-bios.hex", mem, 0);
   end

   always @(posedge clk) begin
     dout <= mem[a[15:0]];
   end
endmodule
