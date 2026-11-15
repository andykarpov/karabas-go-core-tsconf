// generated from ymfm attenuation_to_volume power table (BSD-3, Aaron Giles)
// Only every 4th entry is used (index = attenuation[5:0] << 2), so the table
// holds 64 words. Two read ports (left/right) share one M9K.
module opl4_powtab(input clk, input [5:0] a1, input [5:0] a2,
                   output reg [12:0] q1, output reg [12:0] q2);
(* ramstyle = "M9K" *) reg [12:0] rom [0:63];
initial begin
	rom[0] = 13'h1fe8;
	rom[1] = 13'h1f90;
	rom[2] = 13'h1f3c;
	rom[3] = 13'h1ee4;
	rom[4] = 13'h1e90;
	rom[5] = 13'h1e3c;
	rom[6] = 13'h1de8;
	rom[7] = 13'h1d94;
	rom[8] = 13'h1d44;
	rom[9] = 13'h1cf4;
	rom[10] = 13'h1ca4;
	rom[11] = 13'h1c54;
	rom[12] = 13'h1c08;
	rom[13] = 13'h1bb8;
	rom[14] = 13'h1b6c;
	rom[15] = 13'h1b20;
	rom[16] = 13'h1ad4;
	rom[17] = 13'h1a8c;
	rom[18] = 13'h1a44;
	rom[19] = 13'h19fc;
	rom[20] = 13'h19b4;
	rom[21] = 13'h196c;
	rom[22] = 13'h1924;
	rom[23] = 13'h18e0;
	rom[24] = 13'h189c;
	rom[25] = 13'h1858;
	rom[26] = 13'h1814;
	rom[27] = 13'h17d4;
	rom[28] = 13'h1790;
	rom[29] = 13'h1750;
	rom[30] = 13'h1710;
	rom[31] = 13'h16d0;
	rom[32] = 13'h1690;
	rom[33] = 13'h1654;
	rom[34] = 13'h1614;
	rom[35] = 13'h15d8;
	rom[36] = 13'h159c;
	rom[37] = 13'h1560;
	rom[38] = 13'h1524;
	rom[39] = 13'h14ec;
	rom[40] = 13'h14b0;
	rom[41] = 13'h1478;
	rom[42] = 13'h1440;
	rom[43] = 13'h1408;
	rom[44] = 13'h13d0;
	rom[45] = 13'h139c;
	rom[46] = 13'h1364;
	rom[47] = 13'h1330;
	rom[48] = 13'h12f8;
	rom[49] = 13'h12c4;
	rom[50] = 13'h1290;
	rom[51] = 13'h1260;
	rom[52] = 13'h122c;
	rom[53] = 13'h11f8;
	rom[54] = 13'h11c8;
	rom[55] = 13'h1198;
	rom[56] = 13'h1168;
	rom[57] = 13'h1138;
	rom[58] = 13'h1108;
	rom[59] = 13'h10d8;
	rom[60] = 13'h10a8;
	rom[61] = 13'h107c;
	rom[62] = 13'h1050;
	rom[63] = 13'h1020;
end
always @(posedge clk) q1 <= rom[a1];
always @(posedge clk) q2 <= rom[a2];
endmodule
