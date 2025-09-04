//`default_nettype none

module gs(
	input wire 				CLK,
	input wire				RESET,
	input wire				CE,
	
	input wire [15:0]		A,
	input wire [7:0]		DI,
	output wire [7:0]		DO,
	output wire				OE,
	input wire 				WR_n,
	input wire				RD_n,
	input wire				IORQ_n,
	input wire				M1_n,
	
	output wire	[20:0]	MA,
	input wire [7:0]		MDI,
	output wire [7:0]		MDO,
	output wire				MRFSH_n,
	output wire 			MWE_n,
	output wire				MRD_n,
	
	output wire signed [14:0]	OUT_L,
	output wire signed [14:0]	OUT_R
);

localparam INT = 373; // -- 14MHz / 373 = 0.0375MHz = 37.5kHz samplerate

// cs from host
wire gs_sel = ~IORQ_n & M1_n & (A[7:4] == 4'hB && A[2:0] == 3'h3);
wire gs_cs_n = IORQ_n | ~gs_sel;
wire a = A[3];

// чтение со стороны спектрума #BB, #B3
assign DO = (a) ? {bit7_flag, 6'b111111, bit0_flag} : port_xx03_reg;

// z80 cpu
wire cpu_m1_n, cpu_mreq_n, cpu_iorq_n, cpu_rd_n, cpu_wr_n, cpu_rfsh_n;
wire [15:0] cpu_a_bus;
wire [7:0] cpu_di_bus, cpu_do_bus;
reg int_n;
t80s #(.Mode(0), .T2Write(1), .IOWait(1)) z80_unit (
	.RESET_n					(~RESET),
	.CLK						(CLK),
	.CEN						(CE),
	.WAIT_n					(1'b1),
	.INT_n					(int_n),
	.NMI_n					(1'b1),
	.BUSRQ_n					(1'b1),
	.M1_n						(cpu_m1_n),
	.MREQ_n					(cpu_mreq_n),
	.IORQ_n					(cpu_iorq_n),
	.RD_n						(cpu_rd_n),
	.WR_n						(cpu_wr_n),
	.RFSH_n					(cpu_rfsh_n),
	.HALT_n					(),
	.BUSAK_n					(),
	.A							(cpu_a_bus),
	.DI						(cpu_di_bus),
	.DO						(cpu_do_bus)
);

// int generator
reg [9:0] cnt;
always @(posedge CLK) begin
	if (RESET) begin
		cnt <= 0;
		int_n <= 1;
	end else if (CE) begin
		cnt <= cnt + 1;
		if (cnt == INT) begin
			cnt <= 0;
			int_n <= 0;
		end
	end
	
	if (~cpu_iorq_n & ~cpu_m1_n) int_n <= 1;
end

// ports
reg bit7_flag, bit0_flag;
reg [7:0] port_xxbb_reg, port_xxb3_reg, port_xx03_reg;
reg [5:0] port_xx00_reg;
reg signed [6:0] port_xx06_reg, port_xx07_reg, port_xx08_reg, port_xx09_reg;
reg signed [7:0] ch_a_reg, ch_b_reg, ch_c_reg, ch_d_reg;
reg [6:0] mem;

always @(posedge CLK) begin
	if (~cpu_iorq_n & cpu_m1_n) begin
		case(cpu_a_bus[3:0])
			'h2: bit7_flag <= 0;
			'h3: bit7_flag <= 1;
			'h5: bit0_flag <= 0;
			'hA: bit7_flag <= ~port_xx00_reg[0];
			'hB: bit0_flag <= port_xx09_reg[5];
		endcase
	end
	if (~gs_cs_n) begin
		if (~a & ~RD_n) bit7_flag <= 0;
		if (~a & ~WR_n) bit7_flag <= 1;
		if ( a & ~WR_n) bit0_flag <= 1;
	end
end

// запись со стороны спектрума
always @(posedge CLK)
begin
 	if (RESET) begin
		port_xxbb_reg <= 0;
		port_xxb3_reg <= 0;
	end
	else begin
		if (~gs_cs_n && ~WR_n) begin
			if (a) port_xxbb_reg <= DI;
			else port_xxb3_reg <= DI;
		end
	end
end

// порты звука
always @(posedge CLK)
begin
	if (RESET) begin
		port_xx00_reg <= 0;
      port_xx03_reg <= 0;
	end
	else begin
	
		if (~cpu_iorq_n && ~cpu_wr_n) begin 
			case(cpu_a_bus[3:0])
				0: port_xx00_reg <= cpu_do_bus[5:0];
				3: port_xx03_reg <= cpu_do_bus; 
				6: port_xx06_reg <= cpu_do_bus[5:0];
				7: port_xx07_reg <= cpu_do_bus[5:0];
				8: port_xx08_reg <= cpu_do_bus[5:0];
				9: port_xx09_reg <= cpu_do_bus[5:0];
			endcase
		end
		
		if (~cpu_mreq_n && ~cpu_rd_n && cpu_a_bus[15:13] == 3) begin
			case(cpu_a_bus[9:8])
				0: ch_a_reg <= {~MDI[7], MDI[6:0]};
				1: ch_b_reg <= {~MDI[7], MDI[6:0]};
				2: ch_c_reg <= {~MDI[7], MDI[6:0]};
				3: ch_d_reg <= {~MDI[7], MDI[6:0]};
			endcase
		end

		case (cpu_a_bus[15:14])
			2'b00: mem <= 7'b0000000;  // #0000 - #3FFF  -   16Kb 
			2'b01: mem <= 7'b0000010;	// #4000 - #7FFF  -   16Kb   
			default: mem <= {port_xx00_reg[5:0],  cpu_a_bus[14]};	// #8000 - #FFFF  -     32Kb
		endcase
	end
end

// Шина данных CPU
assign cpu_di_bus = 
	(~cpu_mreq_n && ~cpu_rd_n) ? MDI : 
	(~cpu_iorq_n && ~cpu_rd_n && cpu_a_bus[3:0] == 4'h4) ? {bit7_flag, 6'b111111, bit0_flag} : 
	(~cpu_iorq_n && ~cpu_rd_n && cpu_a_bus[3:0] == 4'h1) ? port_xxbb_reg : 
	(~cpu_iorq_n && ~cpu_rd_n && cpu_a_bus[3:0] == 4'h2) ? port_xxb3_reg : 8'hFF;

assign MA = {mem, cpu_a_bus[13:0]};
assign MDO = cpu_do_bus;
assign MWE_n = cpu_wr_n || cpu_mreq_n || ~(mem[6] || mem[5] || mem[4] || mem[3] || mem[2] || mem[1]);
assign MRD_n = cpu_rd_n || cpu_mreq_n;
assign MRFSH_n = cpu_rfsh_n;
assign OE = (~IORQ_n && ~RD_n && A[7:4] == 4'b1011 && A[2:0] == 3'b011) ? 1'b1 : 1'b0;

// sound mix
reg signed [14:0] out_a, out_b, out_c, out_d;
reg signed [14:0] mix_l, mix_r;
always @(posedge CLK)
begin 
	//if (CE) begin
		out_a <= ch_a_reg * port_xx06_reg;
		out_b <= ch_b_reg * port_xx07_reg;
		out_c <= ch_c_reg * port_xx08_reg;
		out_d <= ch_d_reg * port_xx09_reg;		
		mix_l <= out_a + out_b;
		mix_r <= out_c + out_d;
	//end
end

assign OUT_L = mix_l;
assign OUT_R = mix_r;

endmodule
