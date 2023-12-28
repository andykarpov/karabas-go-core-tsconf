`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date:    13:42:23 03/26/2021 
// Design Name: 
// Module Name:    vdac 
// Project Name: 
// Target Devices: 
// Tool versions: 
// Description: 
//
// Dependencies: 
//
// Revision: 
// Revision 0.01 - File Created
// Additional Comments: 
//
//////////////////////////////////////////////////////////////////////////////////
module vdac
(
  input wire       clk,
  input wire  [4:0] vred_raw,  
  input wire  [4:0] vgrn_raw,
  input wire  [4:0] vblu_raw,
  input wire        vdac_mode,
  input wire        hsync,
  input wire        vsync,
  output reg  [7:0] red_o,
  output reg  [7:0] grn_o,
  output reg  [7:0] blu_o,
  output reg        hsync_o,
  output reg        vsync_o  
);

wire [7:0] red;
wire [7:0] grn;
wire [7:0] blu;

lut redlut (.in(vred_raw), .mode(vdac_mode), .out(red));
lut grnlut (.in(vgrn_raw), .mode(vdac_mode), .out(grn));
lut blulut (.in(vblu_raw), .mode(vdac_mode), .out(blu));

always @ (posedge clk)
begin
  hsync_o <= hsync;
  vsync_o <= vsync;
  red_o <= red;
  grn_o <= grn;
  blu_o <= blu;
end

endmodule

module lut
(
  input wire  [4:0] in,
  input wire        mode,
  output wire [7:0] out
);

  reg [7:0] lut;
  assign out = mode ? {in, in[4:2]} : lut[7:0];

    always @*
        case (in)
            5'd0:    lut = 8'd0;
            5'd1:    lut = 8'd10;
            5'd2:    lut = 8'd21;
            5'd3:    lut = 8'd31;
            5'd4:    lut = 8'd42;
            5'd5:    lut = 8'd53;
            5'd6:    lut = 8'd63;
            5'd7:    lut = 8'd74;
            5'd8:    lut = 8'd85;
            5'd9:    lut = 8'd95;
            5'd10:   lut = 8'd106;
            5'd11:   lut = 8'd117;
            5'd12:   lut = 8'd127;
            5'd13:   lut = 8'd138;
            5'd14:   lut = 8'd149;
            5'd15:   lut = 8'd159;
            5'd16:   lut = 8'd170;
            5'd17:   lut = 8'd181;
            5'd18:   lut = 8'd191;
            5'd19:   lut = 8'd202;
            5'd20:   lut = 8'd213;
            5'd21:   lut = 8'd223;
            5'd22:   lut = 8'd234;
            5'd23:   lut = 8'd245;
            5'd24:   lut = 8'd255;
            default: lut = 8'd255;
        endcase


endmodule
