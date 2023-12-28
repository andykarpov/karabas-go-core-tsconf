
// Pentevo project (c) NedoPC 2011
// integrates sound features: tapeout, beeper and covox

`include "tune.v"

// `define SDM    // uncommented - sigma-delta, commented - PWM

module sound
(
  input  wire       clk,

  input  wire [7:0] din,

  input  wire       beeper_wr,
  input  wire       covox_wr,

  output reg  [7:0] sound
);

//  reg [7:0] val = 0;

// port writes
  always @(posedge clk)
    if (covox_wr)
      sound <= din;
    else if (beeper_wr)
      sound <= din[4] ? 8'hFF : 8'h00;
      
endmodule

