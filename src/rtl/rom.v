`timescale 1ns / 1ps

// The 64K of the TS-BIOS, loaded by the mcu (loader_a[31] = 0), read by the cpu one clock later.
module rom (
    input wire clk,
    input wire [15:0] a,
    output wire [7:0] dout,
	 
	 input wire loader_act,
	 input wire [31:0] loader_a,
	 input wire [7:0] loader_d,
	 input wire loader_wr
    );

	kg_sdpram #(.DW(8), .AW(16)) mem (
		.clka(clk),
		.wea(loader_act & loader_wr & ~loader_a[31]),
		.addra(loader_a[15:0]),
		.dina(loader_d),
		.clkb(clk),
		.enb(1'b1),
		.addrb(a),
		.doutb(dout)
	);

endmodule
