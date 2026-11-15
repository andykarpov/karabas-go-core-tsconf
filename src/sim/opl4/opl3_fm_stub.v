// FM part stub for this test (iverilog cannot read the SystemVerilog core;
// the FM part has its own test in sim/opl3)
module opl3_fm (input clk, input reset_a, input wr_tgl, input [16:0] wr_word, input tick_tgl,
                output [19:0] out_l, output [19:0] out_r);
assign out_l = 20'd0;
assign out_r = 20'd0;
endmodule
