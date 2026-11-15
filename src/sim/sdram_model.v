`timescale 1ns / 1ps
/*
 sdram_model.v (taken from karabas-go-core-archie, with CL 3): the MT48LC16M16A2 of the board for
 Verilator / iverilog (no delays): 4 banks x 8192 rows x 512 columns of 16 bits, CAS latency CL
 (2 or 3), burst 1, auto precharge (A10 of READ / WRITE), DQM.
 The SDRAM edge is the falling edge of clk (SDR_CLK = clk inverted in the tops). A READ at SDRAM edge n
 drives DQ from edge n + 1 (after tAC) until edge n + 2 (tOH): here dq holds the word between the two
 edges after n + 1, which the controller samples at edge n + 2 (its IOB flip-flop on the falling edge);
 with CL 3 one edge later. The read word is masked by DQM of edge n + CL - 2 (DQM read latency 2):
 a masked byte reads as X.
 Checks, counted in clocks (period CLK_NS): tRCD, tRP, tRAS, tRC (ACTIVE to ACTIVE of a bank, REFRESH to
 ACTIVE), tWR, tRFC, a READ / WRITE to a closed bank, an ACTIVE to an open bank, the mode register
 (CL 2, burst 1) before the first ACTIVE, the refresh rate (the longest gap between two refreshes in
 a window of 8192). errors counts them; the first ones are printed.
*/
module sdram_model #(
	parameter real CLK_NS = 11.905,
	parameter integer CL = 2,
	parameter integer ROW_BITS = 13      // rows kept (low bits of the row): fewer for ISim
) (
	input wire clk,
	input wire [1:0] ba,
	input wire [12:0] a,
	input wire [1:0] dqm,
	input wire ras_n,
	input wire cas_n,
	input wire we_n,
	inout wire [15:0] dq
);

reg [15:0] mem [0:(1 << (ROW_BITS + 11)) - 1] /* verilator public */;

integer errors = 0;
integer refreshes = 0;
reg mode_ok = 1'b0;
reg [12:0] row [0:3];
reg open_b [0:3];
integer t = 0;                        // SDRAM clock count
integer t_act [0:3];
integer t_pre [0:3];                  // a precharge took effect (explicit or auto, after tWR / the read)
integer t_wr [0:3];                   // last WRITE
integer t_ref = -100;
integer t_any_act = -100;
integer i;
initial begin
	for (i = 0; i < 4; i = i + 1) begin
		open_b[i] = 1'b0;
		t_act[i] = -100;
		t_pre[i] = -100;
		t_wr[i] = -100;
		row[i] = 13'd0;
	end
end

// tRCD 18, tRP 18, tRC 60, tWR 12 (1 clock + 6 ns), tRFC 66 ns, in clocks
localparam integer C_RCD = 2, C_RP = 2, C_RC = 6, C_WR = 2, C_RFC = 6, C_RAS = 4;   // tRAS 42 ns

reg [15:0] q1 = 16'd0, qm = 16'd0, q2 = 16'd0;
reg v1 = 1'b0, vm = 1'b0, v2 = 1'b0;
reg [1:0] dqm_d1 = 2'b11;
assign dq = v2 ? q2 : 16'bz;

task err(input [8*48-1:0] what);
	begin
		errors = errors + 1;
		if (errors <= 10) $display("SDRAM %0d: %0s (bank %0d, t %0d)", errors, what, ba, t);
	end
endtask

wire [2:0] cmd = { ras_n, cas_n, we_n };
wire [12:0] row_ba = row[ba];
wire [ROW_BITS + 10:0] waddr = { ba, row_ba[ROW_BITS - 1:0], a[8:0] };

always @(negedge clk) begin
	t = t + 1;
	dqm_d1 <= dqm;
	if (CL == 3) begin
		vm <= v1; qm <= q1;
		v2 <= vm;
		q2 <= {dqm_d1[1] ? 8'hxx : qm[15:8], dqm_d1[0] ? 8'hxx : qm[7:0]};
	end else begin
		v2 <= v1;
		q2 <= {dqm_d1[1] ? 8'hxx : q1[15:8], dqm_d1[0] ? 8'hxx : q1[7:0]};
	end
	v1 <= 1'b0;
	case (cmd)
	3'b011: begin  // ACTIVE
		if (!mode_ok) err("ACTIVE before the mode register");
		if (open_b[ba]) err("ACTIVE to an open bank");
		if (t - t_act[ba] < C_RC) err("tRC");
		if (t - t_pre[ba] < C_RP) err("tRP");
		if (t - t_ref < C_RFC) err("tRFC");
		open_b[ba] = 1'b1;
		row[ba] = a;
		t_act[ba] = t;
	end
	3'b101, 3'b100: begin  // READ, WRITE
		if (!open_b[ba]) err("READ / WRITE to a closed bank");
		if (t - t_act[ba] < C_RCD) err("tRCD");
		if (cmd == 3'b101) begin
			v1 <= 1'b1;
			q1 <= mem[waddr];
		end else begin
			if (!dqm[0]) mem[waddr][7:0] = dq[7:0];
			if (!dqm[1]) mem[waddr][15:8] = dq[15:8];
			t_wr[ba] = t;
		end
		if (a[10]) begin   // auto precharge: the bank closes after the access (a write: after tWR)
			if (((cmd == 3'b100) ? t + C_WR : t + 1) - t_act[ba] < C_RAS) err("tRAS (auto precharge)");
			open_b[ba] = 1'b0;
			t_pre[ba] = (cmd == 3'b100) ? t + C_WR : t + 1;
		end
	end
	3'b010: begin  // PRECHARGE
		if (a[10]) begin
			for (i = 0; i < 4; i = i + 1) begin
				if (open_b[i] && t - t_wr[i] < C_WR) err("tWR");
				if (open_b[i] && t - t_act[i] < C_RAS) err("tRAS");
				open_b[i] = 1'b0;
				t_pre[i] = t;
			end
		end else begin
			if (open_b[ba] && t - t_wr[ba] < C_WR) err("tWR");
			if (open_b[ba] && t - t_act[ba] < C_RAS) err("tRAS");
			open_b[ba] = 1'b0;
			t_pre[ba] = t;
		end
	end
	3'b001: begin  // REFRESH
		for (i = 0; i < 4; i = i + 1) begin
			if (open_b[i]) err("REFRESH with an open bank");
			if (t - t_pre[i] < C_RP) err("tRP before REFRESH");
		end
		if (t - t_ref < C_RFC) err("tRFC");
		t_ref = t;
		refreshes = refreshes + 1;
	end
	3'b000: begin  // LOAD MODE
		if (a[6:4] != CL || a[2:0] != 3'b000) err("mode: not CL / burst 1");
		mode_ok = 1'b1;
	end
	default: ;
	endcase
end

endmodule
