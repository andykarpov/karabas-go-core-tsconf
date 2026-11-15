`timescale 1ns / 1ps
`default_nettype none
//
// sdram2p.v: SDRAM controller with two ports for the sound of the TS-Conf (General Sound on port 1,
// the OPL4 sample memory on port 2), the MT48LC16M16A2 of the Karabas Go / Mini / Mini G.
//
// Made from sdram.v of the MiST board (https://github.com/mist-devel/mist-board):
// Copyright (c) 2013 Till Harbaum <till@harbaum.org>
// Copyright (c) 2019 Gyorgy Szombathelyi
//
// This source file is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// Changes for the Karabas Go:
// - SDR_CLK is clk inverted (ODDR2, as in the former sdram.vhd): the SDRAM takes the commands on the
//   falling edge of clk, half a period after they leave the registers; the read data is taken on the
//   falling edge of clk (an IOB flip-flop, the edge where the SDRAM holds it for tOH) and once more on
//   the rising edge.
// - a fixed cycle of 8 clocks (95 ns at 84 MHz): port 1 RAS at t0, CAS at t3, port 2 RAS at t2,
//   CAS at t5, CL 3, single words with auto precharge; port 1 has banks 0 / 1, port 2 banks 2 / 3,
//   so each port gets one access in every cycle; only a port 2 write waits for a cycle without a
//   port 1 read (its data on DQ would meet the read data of port 1).
// - a refresh every 7.4 us at most (624 clocks), in the port 2 slot when port 2 has no request and
//   port 1 has no access in this cycle; when it is urgent the ports skip a cycle for it.
// - no clkref; init_n from the PLL lock.
//
// Ports: a request is a toggle of portN_req (the address, ds, we, d held until the ack); portN_ack
// follows portN_req when it is done. A read: portN_q valid from the clock where portN_ack follows,
// held until the next read of that port.
//
module sdram2p (
	// interface to the MT48LC16M16 chip
	inout  wire [15:0] SDRAM_DQ,   // 16 bit bidirectional data bus
	output reg  [12:0] SDRAM_A,    // 13 bit multiplexed address bus
	output reg         SDRAM_DQML, // two byte masks
	output reg         SDRAM_DQMH, // two byte masks
	output reg   [1:0] SDRAM_BA,   // two banks
	output wire        SDRAM_nWE,  // write enable
	output wire        SDRAM_nRAS, // row address select
	output wire        SDRAM_nCAS, // columns address select
	output wire        SDRAM_CLK,

	input  wire        init_n,     // 0: (re)initialise the SDRAM (PLL not locked)
	input  wire        clk,        // sdram clock, 84 MHz

	input  wire        port1_req,
	output wire        port1_ack,
	input  wire        port1_we,
	input  wire [23:1] port1_a,
	input  wire  [1:0] port1_ds,
	input  wire [15:0] port1_d,
	output wire [15:0] port1_q,

	input  wire        port2_req,
	output wire        port2_ack,
	input  wire        port2_we,
	input  wire [23:1] port2_a,
	input  wire  [1:0] port2_ds,
	input  wire [15:0] port2_d,
	output wire [15:0] port2_q
);

localparam RASCAS_DELAY   = 3'd3;   // tRCD = 20 ns -> 2 cycles @ <= 100 MHz, 3 cycles @ > 100 MHz
localparam BURST_LENGTH   = 3'b000; // 000=1, 001=2, 010=4, 011=8
localparam ACCESS_TYPE    = 1'b0;   // 0=sequential, 1=interleaved
localparam CAS_LATENCY    = 3'd3;   // 2/3 allowed
localparam OP_MODE        = 2'b00;  // only 00 (standard operation) allowed
localparam NO_WRITE_BURST = 1'b1;   // 0= write burst enabled, 1=only single access write

localparam MODE = { 3'b000, NO_WRITE_BURST, OP_MODE, CAS_LATENCY, ACCESS_TYPE, BURST_LENGTH};

// 64 ms / 8192 rows = 7.8 us -> 656 clocks at 84.09 MHz: a refresh is due after 600 clocks (in a cycle
// where the ports leave room for it), urgent after 624 (then both ports skip a cycle)
localparam RFRSH_CYCLES = 11'd600;
localparam RFRSH_URGENT = 11'd624;

// ---------------------------------------------------------------------
// ------------------------ cycle state machine ------------------------
// ---------------------------------------------------------------------

/*
 SDRAM state machine for 2 bank interleaved access, 1 word burst, CL3.
 t is the value of the counter in a clock; a command set in clock t is on the pins in clock t + 1
 and the SDRAM takes it at the falling edge in the middle of it (t + 1.5).
 t0 RAS0   port 1 ACTIVE      (SDRAM edge 1.5)
 t2 RAS1   port 2 ACTIVE      (3.5) or REFRESH
 t3 CAS0   port 1 READ/WRITE  (4.5), write data on DQ in t4
 t5 CAS1   port 2 READ/WRITE  (6.5), write data on DQ in t6
           port 1 read data taken at 7.5 (falling edge), in sd_din in t0
 t0 READ0  port1_q, port1_ack
           port 2 read data taken at 9.5 = 1.5, in sd_din in t2
 t2 READ1  port2_q, port2_ack
*/

localparam STATE_RAS0      = 3'd0;   // first state in cycle
localparam STATE_RAS1      = 3'd2;   // Second ACTIVE command after RAS0 + tRRD (15ns)
localparam STATE_CAS0      = STATE_RAS0 + RASCAS_DELAY; // CAS phase - 3
localparam STATE_DS0       = STATE_RAS0 + RASCAS_DELAY + 1'd1;
localparam STATE_CAS1      = STATE_RAS1 + RASCAS_DELAY; // CAS phase - 5
localparam STATE_DS1       = STATE_RAS1 + RASCAS_DELAY + 1'd1;
localparam STATE_READ0     = 3'd0;
localparam STATE_READ1     = 3'd2;
localparam STATE_LAST      = 3'd7;

reg [2:0] t = 3'd0;

always @(posedge clk) begin
	t <= t + 1'd1;
	if (t == STATE_LAST) t <= STATE_RAS0;
end

// ---------------------------------------------------------------------
// --------------------------- startup/reset ---------------------------
// ---------------------------------------------------------------------

// after init_n: 31 cycles of 8 clocks, the SDRAM initialised in the last 16 (the FPGA configuration
// takes far longer than the 100 us the SDRAM needs after power-up)
reg [4:0]  reset = 5'h1f;
reg        init = 1'b1;
always @(posedge clk, negedge init_n) begin
	if(!init_n) begin
		reset <= 5'h1f;
		init <= 1'b1;
	end else begin
		if((t == STATE_LAST) && (reset != 0)) reset <= reset - 5'd1;
		init <= !(reset == 0);
	end
end

// ---------------------------------------------------------------------
// ------------------ generate ram control signals ---------------------
// ---------------------------------------------------------------------

// all possible commands
localparam CMD_INHIBIT         = 4'b1111;
localparam CMD_NOP             = 4'b0111;
localparam CMD_ACTIVE          = 4'b0011;
localparam CMD_READ            = 4'b0101;
localparam CMD_WRITE           = 4'b0100;
localparam CMD_BURST_TERMINATE = 4'b0110;
localparam CMD_PRECHARGE       = 4'b0010;
localparam CMD_AUTO_REFRESH    = 4'b0001;
localparam CMD_LOAD_MODE       = 4'b0000;

reg  [3:0] sd_cmd = CMD_NOP;   // current command sent to sd ram
reg [15:0] sd_din_n = 16'd0;   // DQ on the falling edge (IOB)
reg [15:0] sd_din = 16'd0;     // and on the rising edge
// drive control signals according to current command
assign SDRAM_nRAS = sd_cmd[2];
assign SDRAM_nCAS = sd_cmd[1];
assign SDRAM_nWE  = sd_cmd[0];

reg [24:1] addr_latch0 = 24'd0, addr_latch1 = 24'd0;
reg [24:1] addr_latch_next0, addr_latch_next1;
reg [15:0] din_latch0 = 16'd0, din_latch1 = 16'd0;
reg  [1:0] oe_latch = 2'b00;
reg  [1:0] we_latch = 2'b00;
reg  [1:0] ds0 = 2'b00, ds1 = 2'b00;
reg  [1:0] state = 2'b00;

localparam PORT_NONE  = 1'd0;
localparam PORT_REQ   = 1'd1;

reg  [1:0] next_port;

reg        port1_ack_reg = 1'b0;
reg [15:0] port1_q_reg = 16'd0;

reg        port2_ack_reg = 1'b0;
reg [15:0] port2_q_reg = 16'd0;

reg        refresh = 1'b0;
reg [10:0] refresh_cnt = 11'd0;
wire       need_refresh = (refresh_cnt >= RFRSH_CYCLES);
wire       urgent_refresh = (refresh_cnt >= RFRSH_URGENT);

// PORT1: bank 0,1
always @(*) begin
	if (refresh || urgent_refresh) begin
		next_port[0] = PORT_NONE;
		addr_latch_next0 = addr_latch0;
	end else if (port1_req ^ state[0]) begin
		next_port[0] = PORT_REQ;
		addr_latch_next0 = { 1'b0, port1_a };
	end else begin
		next_port[0] = PORT_NONE;
		addr_latch_next0 = addr_latch0;
	end
end

// PORT2: bank 2,3
always @(*) begin
	if ((port2_req ^ state[1]) && !urgent_refresh) begin
		next_port[1] = PORT_REQ;
		addr_latch_next1 = { 1'b1, port2_a };
	end else begin
		next_port[1] = PORT_NONE;
		addr_latch_next1 = addr_latch1;
	end
end

reg dir = 1'b1;
reg [15:0] dq = 16'd0;
assign SDRAM_DQ = (dir) ? 16'bZZZZZZZZZZZZZZZZ : dq;

always @(negedge clk)
	sd_din_n <= SDRAM_DQ;

always @(posedge clk) begin

	sd_din <= sd_din_n;
	dir <= 1'b1;
	{ SDRAM_DQMH, SDRAM_DQML } <= 2'b11;
	sd_cmd <= CMD_NOP;  // default: idle
	if (!urgent_refresh) refresh_cnt <= refresh_cnt + 1'd1;

	if(init) begin
		// initialization takes place at the end of the reset phase
		{ oe_latch, we_latch } <= 4'b0000;
		if(t == STATE_RAS0) begin

			if(reset == 15) begin
				sd_cmd <= CMD_PRECHARGE;
				SDRAM_A[10] <= 1'b1;      // precharge all banks
			end

			if(reset == 10 || reset == 8) begin
				sd_cmd <= CMD_AUTO_REFRESH;
			end

			if(reset == 2) begin
				sd_cmd <= CMD_LOAD_MODE;
				SDRAM_A <= MODE;
				SDRAM_BA <= 2'b00;
			end
		end
	end else begin
		// RAS phase
		// bank 0,1
		if(t == STATE_RAS0) begin
			addr_latch0 <= addr_latch_next0;
			{ oe_latch[0], we_latch[0] } <= 2'b00;

			if (next_port[0] != PORT_NONE) begin
				state[0] <= port1_req;
				sd_cmd <= CMD_ACTIVE;
				SDRAM_A <= addr_latch_next0[22:10];
				SDRAM_BA <= addr_latch_next0[24:23];
				{ oe_latch[0], we_latch[0] } <= { ~port1_we, port1_we };
				ds0 <= port1_ds;
				din_latch0 <= port1_d;
			end
		end

		// bank 2,3
		if(t == STATE_RAS1) begin
			refresh <= 1'b0;
			addr_latch1 <= addr_latch_next1;
			{ oe_latch[1], we_latch[1] } <= 2'b00;

			// a port 2 write drives DQ in t6, while the SDRAM turns on the read data of port 1 for
			// its falling edge 7.5: the write waits for a cycle without a port 1 read
			if (next_port[1] != PORT_NONE && !(port2_we && oe_latch[0])) begin
				state[1] <= port2_req;
				sd_cmd <= CMD_ACTIVE;
				SDRAM_A <= addr_latch_next1[22:10];
				SDRAM_BA <= addr_latch_next1[24:23];
				{ oe_latch[1], we_latch[1] } <= { ~port2_we, port2_we };
				ds1 <= port2_ds;
				din_latch1 <= port2_d;
			end

			if (next_port[1] == PORT_NONE && need_refresh && !we_latch[0] && !oe_latch[0]) begin
				refresh <= 1'b1;
				refresh_cnt <= 11'd0;
				sd_cmd <= CMD_AUTO_REFRESH;
			end
		end

		// CAS phase
		if(t == STATE_CAS0 && (we_latch[0] || oe_latch[0])) begin
			sd_cmd <= we_latch[0]?CMD_WRITE:CMD_READ;
			{ SDRAM_DQMH, SDRAM_DQML } <= ~ds0;
			if (we_latch[0]) begin
				dir <= 1'b0;
				dq <= din_latch0;
				port1_ack_reg <= port1_req;
			end
			SDRAM_A <= { 4'b0010, addr_latch0[9:1] };  // auto precharge
			SDRAM_BA <= addr_latch0[24:23];
		end

		if(t == STATE_CAS1 && (we_latch[1] || oe_latch[1])) begin
			sd_cmd <= we_latch[1]?CMD_WRITE:CMD_READ;
			{ SDRAM_DQMH, SDRAM_DQML } <= ~ds1;
			if (we_latch[1]) begin
				dir <= 1'b0;
				dq <= din_latch1;
				port2_ack_reg <= port2_req;
			end
			SDRAM_A <= { 4'b0010, addr_latch1[9:1] };  // auto precharge
			SDRAM_BA <= addr_latch1[24:23];
		end

		// Data returned
		if(t == STATE_DS0 && oe_latch[0])	{ SDRAM_DQMH, SDRAM_DQML } <= ~ds0;

		if(t == STATE_READ0 && oe_latch[0]) begin
			port1_q_reg <= sd_din;
			port1_ack_reg <= port1_req;
		end

		if(t == STATE_DS1 && oe_latch[1])	{ SDRAM_DQMH, SDRAM_DQML } <= ~ds1;

		if(t == STATE_READ1 && oe_latch[1]) begin
			port2_q_reg <= sd_din;
			port2_ack_reg <= port2_req;
		end
	end
end

assign port1_q   = (t == STATE_READ0 && oe_latch[0]) ? sd_din : port1_q_reg;
assign port1_ack = (t == STATE_READ0 && oe_latch[0]) ? port1_req : port1_ack_reg;

assign port2_q   = (t == STATE_READ1 && oe_latch[1]) ? sd_din : port2_q_reg;
assign port2_ack = (t == STATE_READ1 && oe_latch[1]) ? port2_req : port2_ack_reg;

// SDR_CLK: clk inverted
ODDR2 #(.DDR_ALIGNMENT("NONE"), .INIT(1'b0), .SRTYPE("SYNC")) u_ck (
	.Q(SDRAM_CLK), .C0(clk), .C1(~clk), .CE(1'b1), .D0(1'b0), .D1(1'b1), .R(1'b0), .S(1'b0)
);

endmodule
`default_nettype wire
