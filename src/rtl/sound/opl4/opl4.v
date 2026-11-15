// ============================================================================
// YMF278B (OPL4) wavetable part for ZX-Evo / U16 TS-Conf
//
// 24-channel PCM engine processed sequentially once per output sample.
// Arithmetic follows ymfm (ymfm_pcm.cpp, BSD-3, Aaron Giles) bit for bit;
// FM synthesis is outside (opl3_fm, fed through fm_w/fm_wword); this module
// keeps the FM address, NEW/NEW2, timers and status, and mixes the FM
// outputs A/B (fm_l/fm_r) into DO2 with the FM mix register 0xF8.
//
// Host side (offsets as in ymfm / ZXM-MoonSound):
//   0 W FM address (bank 0)   R status
//   1 W FM data
//   2 W FM address (bank 1)
//   3 W FM data
//   4 W PCM address
//   5 W PCM data              R PCM data
//   wr      - one clock strobe, wr_off/wr_data valid
//   rd_off  - offset of the read in progress, rd_data follows it
//   rd_done - one clock strobe at the end of a read cycle (side effects)
//
// Memory: 22-bit byte address. Reads return the 16-bit word containing the
// addressed byte (even byte in [7:0], odd byte in [15:8]); writes are byte
// writes. mem_req is held until mem_ack (one clock).
// Writes to addresses below 0x200000 (sample ROM) are dropped.
// ============================================================================
module opl4 (
	input             clk,
	input             reset,

	input             wr,
	input      [2:0]  wr_off,
	input      [7:0]  wr_data,
	input      [2:0]  rd_off,
	output reg [7:0]  rd_data,
	input             rd_done,

	input             sample_tick,
	output reg signed [15:0] do1_l,
	output reg signed [15:0] do1_r,
	output reg signed [15:0] do2_l,
	output reg signed [15:0] do2_r,
	output            idle,
	output            busy,
	output            irq,        // FM timer interrupt (ZXM-MoonSound: to Z80 /INT)

	output reg        fm_w,       // one clock: FM register write fm_wword = {bank, addr, data}
	output reg [16:0] fm_wword,
	input      signed [19:0] fm_l, // FM outputs A/B (sum of channels, operator scale 13 bit)
	input      signed [19:0] fm_r,

	output     [21:0] mem_addr,
	output            mem_req,
	output            mem_we,
	output     [7:0]  mem_wdata,
	input             mem_ack,
	input      [15:0] mem_rdata
);

localparam EG_ATTACK  = 3'd1;
localparam EG_DECAY   = 3'd2;
localparam EG_SUSTAIN = 3'd3;
localparam EG_RELEASE = 3'd4;
localparam EG_REVERB  = 3'd5;

// ---------------------------------------------------------------------------
// shared state between the blocks
// ---------------------------------------------------------------------------
reg         new1, new2, status_id;
reg  [8:0]  fm_addr;
reg  [7:0]  pcm_addr;

reg  [7:0]  r2, r3, r4, r5, rf8, rf9;     // copies of special registers
wire [21:0] memaddr = {r3[5:0], r4, r5};
reg  [7:0]  prefetch;
reg         pref_dirty;
reg  [23:0] wav_hi;                       // bit 0 of regs 0x20..0x37

reg  [23:0] key_pend, key_pend_on, env_reset;
reg  [23:0] key_set, key_on_set, env_set; // pulses from host fsm
reg  [23:0] key_clr, env_clr;             // pulses from engine
reg  [3:0]  ld_cnt;
reg         ld_load, ld_dec;

// ---------------------------------------------------------------------------
// register RAM, one M9K in true dual-port mode
//   port A: register writes, host reads (pcm_addr) when not writing
//   port B: engine reads
// regB_q keeps the last host read while port A is busy writing.
// ---------------------------------------------------------------------------
(* ramstyle = "M9K" *) reg [7:0] regs [0:255];
reg         reg_we;
reg  [7:0]  reg_waddr, reg_wdata;
reg  [7:0]  regA_raddr;
reg  [7:0]  regA_q, regB_q, reg_qa;
reg         reg_we_d;
wire [7:0]  reg_addr_a = reg_we ? reg_waddr : pcm_addr;

always @(posedge clk) begin
	if (reg_we) regs[reg_addr_a] <= reg_wdata;
	reg_qa <= regs[reg_addr_a];
end
always @(posedge clk) regA_q <= regs[regA_raddr];
always @(posedge clk) begin
	reg_we_d <= reg_we;
	if (!reg_we_d) regB_q <= reg_qa;
end

// ---------------------------------------------------------------------------
// per-channel wave header RAM {fmt2, base22, loop16, endneg16}
// ---------------------------------------------------------------------------
reg  [55:0] hdr_ram [0:23];
reg         hdr_we;
reg  [4:0]  hdr_waddr;
reg  [55:0] hdr_wdata;
reg  [4:0]  e_ch;
reg  [55:0] hdr_q;
always @(posedge clk) begin
	if (hdr_we) hdr_ram[hdr_waddr] <= hdr_wdata;
	hdr_q <= hdr_ram[e_ch];
end

// ---------------------------------------------------------------------------
// per-channel state RAM {cur32, next32, lfo18, eg3, env10, tl17, kon1}
// ---------------------------------------------------------------------------
reg  [112:0] st_ram [0:23];
reg          st_we;
reg  [4:0]   st_waddr;
reg  [112:0] st_wdata;
reg  [112:0] st_q;
always @(posedge clk) begin
	if (st_we) st_ram[st_waddr] <= st_wdata;
	st_q <= st_ram[e_ch];
end

// ---------------------------------------------------------------------------
// host write FIFO {kind, addr, data}; kind 1 = memory read advance
// ---------------------------------------------------------------------------
reg  [16:0] fifo [0:31];
reg  [5:0]  fifo_wp, fifo_rp;
reg  [16:0] fifo_q;
wire [5:0]  fifo_cnt = fifo_wp - fifo_rp;
reg         fifo_push;
reg  [16:0] fifo_din;
always @(posedge clk) begin
	if (fifo_push) fifo[fifo_wp[4:0]] <= fifo_din;
	fifo_q <= fifo[fifo_rp[4:0]];
end

// ---------------------------------------------------------------------------
// host interface (immediate part)
// ---------------------------------------------------------------------------
reg [8:0] fm_a;
always @* begin
	fm_a = {1'b1, wr_data};
	if (!new1 && fm_a != 9'h105) fm_a[8] = 1'b0;
end

always @(posedge clk) begin
	fifo_push <= 1'b0;
	ld_load   <= 1'b0;
	fm_w      <= 1'b0;
	if (reset) begin
		new1 <= 1'b0; new2 <= 1'b0; status_id <= 1'b1;
		fm_addr <= 9'd0; pcm_addr <= 8'd0;
		fifo_wp <= 6'd0;
	end else begin
		if (fifo_push) fifo_wp <= fifo_wp + 1'd1;
		if (wr) begin
			case (wr_off)
				3'd0: fm_addr <= {1'b0, wr_data};
				3'd2: fm_addr <= fm_a;
				3'd1, 3'd3: begin
					fm_w     <= 1'b1;
					fm_wword <= {fm_addr, wr_data};
					if (fm_addr == 9'h105) begin
						new1 <= wr_data[0];
						new2 <= wr_data[1];
						if (!new2 && wr_data[1]) status_id <= 1'b1;
					end
				end
				3'd4: pcm_addr <= wr_data;
				3'd5:
					if (new2) begin
						fifo_push <= 1'b1;
						fifo_din  <= {1'b0, pcm_addr, wr_data};
						if (pcm_addr >= 8'h08 && pcm_addr <= 8'h1f) ld_load <= 1'b1;
					end
				default: ;
			endcase
		end
		if (rd_done) begin
			if (rd_off == 3'd0) status_id <= 1'b0;
			if (rd_off == 3'd5 && pcm_addr == 8'h06 && r2[0]) begin
				fifo_push <= 1'b1;
				fifo_din  <= {1'b1, 16'h0000};
			end
		end
	end
end

// ---------------------------------------------------------------------------
// FM timers (OPL3 compatible): reg 2 = timer 1 (80.8 us steps), reg 3 =
// timer 2 (323 us steps), reg 4 = RST/MASK1/MASK2/ST2/ST1
// ---------------------------------------------------------------------------
reg  [7:0]  t1_val, t2_val, t1_cnt, t2_cnt;
reg         t1_st, t2_st, t1_mask, t2_mask, ft1, ft2;
reg  [12:0] t_pre;        // 84 MHz / 6786 = 80.8 us
reg  [1:0]  t_pre2;
wire        t_tick = (t_pre == 13'd6785);
wire        fm_wr  = wr && (wr_off == 3'd1 || wr_off == 3'd3) && !fm_addr[8];
always @(posedge clk) begin
	if (reset) begin
		t1_val <= 8'd0; t2_val <= 8'd0; t1_cnt <= 8'd0; t2_cnt <= 8'd0;
		t1_st <= 1'b0; t2_st <= 1'b0; t1_mask <= 1'b0; t2_mask <= 1'b0;
		ft1 <= 1'b0; ft2 <= 1'b0; t_pre <= 13'd0; t_pre2 <= 2'd0;
	end else begin
		t_pre <= t_tick ? 13'd0 : t_pre + 1'd1;
		if (t_tick) begin
			t_pre2 <= t_pre2 + 1'd1;
			if (t1_st) begin
				if (t1_cnt == 8'hff) begin
					t1_cnt <= t1_val;
					if (!t1_mask) ft1 <= 1'b1;
				end else
					t1_cnt <= t1_cnt + 1'd1;
			end
			if (t2_st && t_pre2 == 2'd3) begin
				if (t2_cnt == 8'hff) begin
					t2_cnt <= t2_val;
					if (!t2_mask) ft2 <= 1'b1;
				end else
					t2_cnt <= t2_cnt + 1'd1;
			end
		end
		if (fm_wr) begin
			case (fm_addr[7:0])
				8'h02: t1_val <= wr_data;
				8'h03: t2_val <= wr_data;
				8'h04:
					if (wr_data[7]) begin
						ft1 <= 1'b0; ft2 <= 1'b0;          // IRQ reset, other bits ignored
					end else begin
						t1_mask <= wr_data[6];
						t2_mask <= wr_data[5];
						if (wr_data[6]) ft1 <= 1'b0;
						if (wr_data[5]) ft2 <= 1'b0;
						t1_st <= wr_data[0];
						t2_st <= wr_data[1];
						if (wr_data[0] && !t1_st) t1_cnt <= t1_val;
						if (wr_data[1] && !t2_st) t2_cnt <= t2_val;
					end
				default: ;
			endcase
		end
	end
end
assign irq = ft1 | ft2;
wire [7:0] fm_status = {ft1 | ft2, ft1, ft2, 5'd0};

// read data
assign busy = (fifo_cnt >= 6'd16) | pref_dirty;
always @* begin
	rd_data = 8'hff;
	case (rd_off)
		3'd0:
			if (status_id)  rd_data = new2 ? 8'h02 : (new1 ? 8'h00 : 8'h06);
			else if (new2)  rd_data = fm_status | {6'd0, ld_cnt != 4'd0, busy};
			else            rd_data = fm_status;
		3'd5:
			case (pcm_addr)
				8'h02: rd_data = r2 | 8'h20;
				8'h03: rd_data = r3;
				8'h04: rd_data = r4;
				8'h05: rd_data = r5;
				8'h06: rd_data = r2[0] ? prefetch : regB_q;
				default: rd_data = regB_q;
			endcase
		default: ;
	endcase
end

// LD counter and per-channel flags
always @(posedge clk) begin
	if (reset) begin
		ld_cnt <= 4'd0;
		key_pend <= 24'd0; key_pend_on <= 24'd0; env_reset <= 24'd0;
	end else begin
		if (ld_load) ld_cnt <= 4'd13;
		else if (ld_dec && ld_cnt != 4'd0) ld_cnt <= ld_cnt - 1'd1;
		key_pend    <= (key_pend    & ~key_clr) | key_set;
		key_pend_on <= (key_pend_on & ~key_clr) | key_on_set;
		env_reset   <= (env_reset   & ~env_clr) | env_set;
	end
end

// ---------------------------------------------------------------------------
// host FSM: applies queued writes, loads wave headers, memory access
// runs only while the engine is idle
// ---------------------------------------------------------------------------
localparam H_INIT = 3'd0, H_IDLE = 3'd1, H_POP = 3'd2, H_HDR = 3'd3,
           H_HDRW = 3'd4, H_MEMW = 3'd5, H_PREF = 3'd6, H_HDRA = 3'd7;
reg  [2:0]  hstate;
reg  [7:0]  hcnt;
reg  [4:0]  hch;
reg  [8:0]  h_wav;
reg  [21:0] h_addr;
reg         h_req, h_we;
reg  [7:0]  h_wdata;
reg  [7:0]  hbuf [0:11];
reg         tick_pend;
wire        e_idle;
wire        e_gap;
wire        h_idle = (hstate == H_IDLE);

wire        f_kind = fifo_q[16];
wire [7:0]  f_addr = fifo_q[15:8];
wire [7:0]  f_data = fifo_q[7:0];
wire [21:0] memaddr_inc = memaddr + 1'd1;

// header address for wave number {wav_hi, data}
wire [8:0]  h_wavnum = {wav_hi[f_addr - 8'h08], f_data};
wire [8:0]  h_wavrel = h_wav - 9'd384;
wire [21:0] h_hdr_addr = (h_wav >= 9'd384 && r2[4:2] != 3'd0) ?
                         ({r2[4:2], 19'd0} + h_wavrel * 4'd12) :
                         (h_wav * 4'd12);

wire [15:0] hdr_end  = {hbuf[5], hbuf[6]};

always @(posedge clk) begin
	reg_we  <= 1'b0;
	hdr_we  <= 1'b0;
	key_set <= 24'd0; key_on_set <= 24'd0; env_set <= 24'd0;
	if (reset) begin
		hstate <= H_INIT;
		hcnt   <= 8'd0;
		h_req  <= 1'b0; h_we <= 1'b0;
		fifo_rp <= 6'd0;
		r2 <= 8'd0; r3 <= 8'd0; r4 <= 8'd0; r5 <= 8'd0; rf8 <= 8'h1b; rf9 <= 8'd0;
		wav_hi <= 24'd0;
		pref_dirty <= 1'b1;
		prefetch <= 8'd0;
	end else case (hstate)
		H_INIT: begin
			reg_we    <= 1'b1;
			reg_waddr <= hcnt;
			reg_wdata <= (hcnt == 8'hf8) ? 8'h1b : 8'h00;
			hdr_we    <= hcnt < 8'd24;
			hdr_waddr <= hcnt[4:0];
			hdr_wdata <= 56'd0;
			hcnt <= hcnt + 1'd1;
			if (hcnt == 8'hff) hstate <= H_IDLE;
		end

		H_IDLE:
			if ((e_idle && !tick_pend && !sample_tick) || e_gap) begin
				if (fifo_cnt != 6'd0)
					hstate <= H_POP;
				else if (pref_dirty) begin
					h_req <= 1'b1; h_we <= 1'b0;
					h_addr <= memaddr;
					pref_dirty <= 1'b0;
					hstate <= H_PREF;
				end
			end

		H_POP: begin
			fifo_rp <= fifo_rp + 1'd1;
			hstate  <= H_IDLE;
			if (f_kind) begin
				r3 <= {2'b00, memaddr_inc[21:16]}; r4 <= memaddr_inc[15:8]; r5 <= memaddr_inc[7:0];
				pref_dirty <= 1'b1;
			end else if (f_addr == 8'h06 && r2[0]) begin
				r3 <= {2'b00, memaddr_inc[21:16]}; r4 <= memaddr_inc[15:8]; r5 <= memaddr_inc[7:0];
				pref_dirty <= 1'b1;
				if (memaddr[21]) begin
					h_req <= 1'b1; h_we <= 1'b1;
					h_addr <= memaddr; h_wdata <= f_data;
					hstate <= H_MEMW;
				end
			end else begin
				reg_we <= 1'b1; reg_waddr <= f_addr; reg_wdata <= f_data;
				case (f_addr)
					8'h02: begin r2 <= f_data; pref_dirty <= 1'b1; end
					8'h03: begin r3 <= f_data; pref_dirty <= 1'b1; end
					8'h04: begin r4 <= f_data; pref_dirty <= 1'b1; end
					8'h05: begin r5 <= f_data; pref_dirty <= 1'b1; end
					8'hf8: rf8 <= f_data;
					8'hf9: rf9 <= f_data;
					default: ;
				endcase
				if (f_addr >= 8'h20 && f_addr <= 8'h37) wav_hi[f_addr - 8'h20] <= f_data[0];
				if (f_addr >= 8'h68 && f_addr <= 8'h7f) begin
					key_set[f_addr - 8'h68] <= 1'b1;
					key_on_set[f_addr - 8'h68] <= f_data[7];
				end
				if (f_addr >= 8'h08 && f_addr <= 8'h1f) begin
					hch    <= f_addr - 8'h08;
					h_wav  <= h_wavnum;
					hstate <= H_HDRA;
				end
			end
		end

		H_HDRA: begin
			h_addr <= h_hdr_addr;
			h_req  <= 1'b1; h_we <= 1'b0;
			hcnt   <= 8'd0;
			hstate <= H_HDR;
		end

		H_HDR:
			if (mem_ack) begin
				hbuf[{hcnt[2:0], 1'b0}] <= mem_rdata[7:0];
				hbuf[{hcnt[2:0], 1'b1}] <= mem_rdata[15:8];
				h_addr <= h_addr + 2'd2;
				if (hcnt == 8'd5) begin
					h_req  <= 1'b0;
					hcnt   <= 8'd0;
					hstate <= H_HDRW;
				end else
					hcnt <= hcnt + 1'd1;
			end

		H_HDRW: begin
			reg_we <= 1'b1;
			case (hcnt[2:0])
				3'd0: begin reg_waddr <= 8'h80 + hch; reg_wdata <= hbuf[7];  end
				3'd1: begin reg_waddr <= 8'h98 + hch; reg_wdata <= hbuf[8];  end
				3'd2: begin reg_waddr <= 8'hb0 + hch; reg_wdata <= hbuf[9];  end
				3'd3: begin reg_waddr <= 8'hc8 + hch; reg_wdata <= hbuf[10]; end
				default: begin reg_waddr <= 8'he0 + hch; reg_wdata <= hbuf[11]; end
			endcase
			if (hcnt == 8'd4) begin
				hdr_we    <= 1'b1;
				hdr_waddr <= hch;
				hdr_wdata <= {hbuf[0], hbuf[1], hbuf[2], hbuf[3], hbuf[4], 16'd0 - hdr_end};
				env_set[hch] <= 1'b1;
				hstate <= H_IDLE;
			end
			hcnt <= hcnt + 1'd1;
		end

		H_MEMW:
			if (mem_ack) begin h_req <= 1'b0; hstate <= H_IDLE; end

		H_PREF:
			if (mem_ack) begin
				h_req <= 1'b0;
				prefetch <= h_addr[0] ? mem_rdata[15:8] : mem_rdata[7:0];
				hstate <= H_IDLE;
			end

	endcase
end

// ---------------------------------------------------------------------------
// tables
// ---------------------------------------------------------------------------
wire [7:0]  pow_a_l, pow_a_r;
wire [12:0] pow_q_l, pow_q_r;
opl4_powtab pow (.clk(clk), .a1(pow_a_l[7:2]), .a2(pow_a_r[7:2]), .q1(pow_q_l), .q2(pow_q_r));

reg  [5:0]  inc_rate;
reg  [2:0]  inc_idx;
wire [3:0]  inc_val;
opl4_inctab inct (.rate(inc_rate), .idx(inc_idx), .inc(inc_val));

function [5:0] effrate;
	input [3:0] raw;
	input signed [7:0] corr;
	reg signed [8:0] t;
	begin
		t = $signed({3'b000, raw, 2'b00}) + corr;
		if (raw == 4'd0)       effrate = 6'd0;
		else if (raw == 4'd15) effrate = 6'd63;
		else if (t < 0)        effrate = 6'd0;
		else if (t > 63)       effrate = 6'd63;
		else                   effrate = t[5:0];
	end
endfunction

// ---------------------------------------------------------------------------
// engine
// ---------------------------------------------------------------------------
localparam E_INIT = 5'd0, E_IDLE = 5'd1, E_START = 5'd2, E_RD = 5'd3,
           E_CACHE = 5'd4, E_PREP = 5'd5, E_CLK1 = 5'd6, E_CLK2 = 5'd7,
           E_FETCH = 5'd8, E_VOL = 5'd9, E_VOL2 = 5'd10, E_MULL = 5'd11,
           E_MULR = 5'd12, E_WB = 5'd13, E_MIX = 5'd14, E_MIX2 = 5'd15,
           E_CLK1B = 5'd16, E_MIX3 = 5'd17,
           E_CLK1C = 5'd18, E_MULR2 = 5'd19, E_GAP = 5'd20,
           E_MIXA = 5'd21, E_MIXB = 5'd22,
           E_MIX0 = 5'd23, E_MIXW1 = 5'd24, E_MIXW2 = 5'd25, E_MIXW3 = 5'd26;
reg  [4:0]  estate;
reg  [3:0]  ecnt;
reg  [14:0] env_cnt;
assign e_idle = (estate == E_IDLE);
// between channels the engine lets queued host operations through, so that
// register/memory accesses take effect within ~1-2 us instead of a whole sample
reg  [7:0]  gap_cnt;
assign e_gap = (estate == E_GAP) && (gap_cnt < 8'd200);
assign idle = e_idle && h_idle && !tick_pend && fifo_cnt == 6'd0 && !pref_dirty && !fifo_push;

// channel registers
reg  [7:0]  r20, r38, r50, r68, r80, r98, rb0, rc8, re0;
// channel state
reg  [31:0] cur, nxt;
reg  [17:0] lfo;
reg  [2:0]  eg;
reg  [9:0]  env;
reg  [16:0] tl;
reg         kon;
// header
reg  [1:0]  fmt;
reg  [21:0] base;
reg  [15:0] loop16, endn16;
// cache
reg  [31:0] c_step;
reg  [16:0] c_tl;
reg  [9:0]  c_panl, c_panr;
reg  [5:0]  c_lfostep;
reg  [7:0]  c_am;
reg  [5:0]  c_pm;
reg  [9:0]  c_sus;
reg  [5:0]  c_ar, c_dr, c_sr, c_rr;
reg  [5:0]  rate;
reg  [31:0] c_lme;      // loop - end
reg  [31:0] nxt_a_r;    // nxt + step (karabas: added in E_CLK1C, one state before E_CLK2)
reg  [31:0] pm_add_r;
reg  [3:0]  inc_r;
reg         fire_r;
reg  [11:0] envl0_r;
reg  signed [29:0] prod_r;
reg  signed [43:0] mix_r;
// output
reg  signed [31:0] acc0, acc1, acc2, acc3;
reg  [2:0]  sc_l, sc_r, fsc_l, fsc_r;
// FM sample of this output period, x2: ymfm (whose PCM part this follows)
// works with 14-bit operator values, Nuked-OPL3 and the FM core with 13-bit
reg  signed [20:0] fm_hl, fm_hr;
reg  signed [15:0] sample;
reg  [12:0] vol_l, vol_r;
reg  [3:0]  sh_l, sh_r;
reg         second;
reg  [21:0] e_addr;
reg         e_req;
reg  [21:0] a_hi, a_lo;
reg  [1:0]  lo_kind;
reg  [7:0]  b_hi;

// combinational helpers ------------------------------------------------------
wire signed [3:0]  oct   = r38[7:4];
wire [9:0]         fnum  = {r38[2:0], r20[7:1]};
wire [4:0]         shamt = oct + 4'sd7;              // x86 masks the count to 5 bits
wire [31:0]        step_full = {21'd0, 1'b1, fnum} << shamt;
wire signed [3:0]  pan   = r68[3:0];
wire [3:0]         sl    = rb0[7:4];
wire [4:0]         sl5   = {1'b0, sl} | ((sl + 5'd1) & 5'h10);
wire [3:0]         rc    = rc8[7:4];
wire signed [7:0]  corr  = (rc == 4'd15) ? 8'sd0 :
                           ((($signed({{4{oct[3]}}, oct}) + $signed({4'd0, rc})) <<< 1) + $signed({7'd0, fnum[9]}));

reg  [5:0]  lfo_step_t;
reg  [7:0]  am_t;
reg  [5:0]  pm_t;
always @* begin
	case (r80[5:3])
		3'd0: lfo_step_t = 6'd1;  3'd1: lfo_step_t = 6'd12; 3'd2: lfo_step_t = 6'd19; 3'd3: lfo_step_t = 6'd25;
		3'd4: lfo_step_t = 6'd31; 3'd5: lfo_step_t = 6'd35; 3'd6: lfo_step_t = 6'd37; default: lfo_step_t = 6'd42;
	endcase
	case (re0[2:0])
		3'd0: am_t = 8'h00; 3'd1: am_t = 8'h14; 3'd2: am_t = 8'h20; 3'd3: am_t = 8'h28;
		3'd4: am_t = 8'h30; 3'd5: am_t = 8'h40; 3'd6: am_t = 8'h50; default: am_t = 8'h80;
	endcase
	case (r80[2:0])
		3'd0: pm_t = 6'd0; 3'd1: pm_t = 6'd2;  3'd2: pm_t = 6'd3;  3'd3: pm_t = 6'd4;
		3'd4: pm_t = 6'd6; 3'd5: pm_t = 6'd12; 3'd6: pm_t = 6'd24; default: pm_t = 6'd48;
	endcase
end

// envelope rate selection (after state transitions)
reg  [2:0]  eg1;
always @* begin
	eg1 = eg;
	if (eg1 == EG_ATTACK && env == 10'd0) eg1 = EG_DECAY;
	if (eg1 == EG_DECAY && env >= c_sus)  eg1 = EG_SUSTAIN;
end

// envelope increment
wire [3:0]  rs     = rate[5:2];
wire [13:0] eparam = env_cnt[14:1];
wire [3:0]  psh    = (rs <= 4'd11) ? (4'd11 - rs) : 4'd0;
wire [13:0] pmask  = (14'd1 << psh) - 1'd1;
wire        e_fire = (eparam & pmask) == 14'd0;
always @* begin
	inc_rate = rate;
	inc_idx  = eparam >> psh;
end
wire signed [15:0] att_prod = -($signed({5'd0, env} + 16'sd1) * $signed({12'd0, inc_r}));
wire        [15:0] att_env  = {6'd0, env} + (att_prod >>> 4);
wire        [10:0] dec_env  = {1'b0, env} + inc_r;

// LFO values
wire [17:0] lfo_sh  = lfo + 18'h10000;
wire [6:0]  lfo_pm7 = lfo_sh[16:10] ^ {7{lfo_sh[17]}};
wire signed [7:0]  lfo_pmv = $signed({1'b0, lfo_pm7}) - 8'sd64;
wire signed [14:0] pm_prod = lfo_pmv * $signed({1'b0, c_pm});
wire signed [31:0] pm_add  = pm_prod >>> 7;
wire [6:0]  lfo_am7 = lfo[16:10] ^ {7{lfo[17]}};
wire [14:0] am_prod = lfo_am7 * c_am;

// position update. karabas: nxt + step is taken in E_CLK1C (nxt is set in E_PREP and kept until
// E_CLK2, the only next state of E_CLK1C), so E_CLK2 has the compare and the loop add side by side
// instead of three carry chains in a row (13.6 ns at 84 MHz on the XC6SLX25). The same numbers:
// endpos has 16 zero bits, nxt_a >= endpos is nxt_a[31:16] >= endn16.
wire [31:0] nxt_a   = nxt_a_r;
wire [31:0] nxt_b   = (nxt_a[31:16] >= endn16) ? (nxt_a + c_lme) : nxt_a;

// volume
wire [11:0] envl0   = {2'd0, env} + am_prod[14:7] + tl[16:8];
wire [11:0] lenv_s  = envl0_r + c_panl;
wire [11:0] renv_s  = envl0_r + c_panr;
wire [9:0]  lenv    = (lenv_s > 12'h3ff) ? 10'h3ff : lenv_s[9:0];
wire [9:0]  renv    = (renv_s > 12'h3ff) ? 10'h3ff : renv_s[9:0];
assign pow_a_l = {lenv[5:0], 2'b00};
assign pow_a_r = {renv[5:0], 2'b00};

// sample fetch addresses (from new current position)
wire [15:0] pos     = cur[31:16];
wire [21:0] a8      = base + pos;
wire [21:0] a16     = base + {pos, 1'b0};
wire [21:0] a12     = base + pos[15:1] * 2'd3;

// multiplier
reg  [12:0] mul_v;
wire signed [29:0] mul_p   = $signed({1'b0, mul_v}) * sample;
wire signed [31:0] mul_sh  = prod_r >>> 15;
reg  signed [31:0] mix_in;
reg  [10:0] mix_k;
wire signed [43:0] mix_p   = mix_in * $signed({1'b0, mix_k});
// karabas: the product through a register (the DSP -> mix_r path missed clk_sys by 0.06 ns on the
// Mini G); E_MIX0 / E_MIXW1..3 wait for it, 4 clocks more per sample (of about 1900), same output
reg  signed [43:0] mix_pr;
always @(posedge clk) mix_pr <= mix_p;
wire signed [43:0] mix_sh  = mix_r >>> 11;

function [10:0] mixscale;
	input [2:0] i;
	case (i)
		3'd0: mixscale = 11'h7fa; 3'd1: mixscale = 11'h5a4; 3'd2: mixscale = 11'h3fd; 3'd3: mixscale = 11'h2d2;
		3'd4: mixscale = 11'h1fe; 3'd5: mixscale = 11'h169; 3'd6: mixscale = 11'h0ff; default: mixscale = 11'h000;
	endcase
endfunction

function signed [15:0] clamp16;
	input signed [43:0] v;
	if (v > 44'sd32767)       clamp16 = 16'sh7fff;
	else if (v < -44'sd32768) clamp16 = 16'sh8000;
	else                      clamp16 = v[15:0];
endfunction

always @(posedge clk) begin
	st_we   <= 1'b0;
	key_clr <= 24'd0;
	env_clr <= 24'd0;
	ld_dec  <= 1'b0;
	if (sample_tick) tick_pend <= 1'b1;
	if (reset) begin
		estate <= E_INIT;
		e_ch   <= 5'd0;
		e_req  <= 1'b0;
		env_cnt <= 15'd0;
		tick_pend <= 1'b0;
		do1_l <= 16'd0; do1_r <= 16'd0; do2_l <= 16'd0; do2_r <= 16'd0;
	end else case (estate)
		E_INIT: begin
			st_we    <= 1'b1;
			st_waddr <= e_ch;
			// cur, next, lfo = 0, eg = RELEASE, env = 0x3ff, tl = 0x7f<<10, key = 0
			st_wdata <= {32'd0, 32'd0, 18'd0, EG_RELEASE, 10'h3ff, 17'h1fc00, 1'b0};
			e_ch <= e_ch + 1'd1;
			if (e_ch == 5'd23) begin e_ch <= 5'd0; estate <= E_IDLE; end
		end

		E_IDLE:
			if (tick_pend && h_idle) begin
				tick_pend <= sample_tick;
				estate <= E_START;
			end

		E_START: begin
			e_ch    <= 5'd0;
			env_cnt <= env_cnt + 1'd1;
			acc0 <= 32'sd0; acc1 <= 32'sd0; acc2 <= 32'sd0; acc3 <= 32'sd0;
			sc_l <= rf9[2:0]; sc_r <= rf9[5:3];
			fsc_l <= rf8[2:0]; fsc_r <= rf8[5:3];
			fm_hl <= {fm_l, 1'b0}; fm_hr <= {fm_r, 1'b0};
			ecnt <= 4'd0;
			regA_raddr <= 8'h20;
			estate <= E_RD;
		end

		E_RD: begin
			ecnt <= ecnt + 1'd1;
			case (ecnt)
				4'd0: regA_raddr <= 8'h38 + e_ch;
				4'd1: regA_raddr <= 8'h50 + e_ch;
				4'd2: regA_raddr <= 8'h68 + e_ch;
				4'd3: regA_raddr <= 8'h80 + e_ch;
				4'd4: regA_raddr <= 8'h98 + e_ch;
				4'd5: regA_raddr <= 8'hb0 + e_ch;
				4'd6: regA_raddr <= 8'hc8 + e_ch;
				4'd7: regA_raddr <= 8'he0 + e_ch;
				default: ;
			endcase
			case (ecnt)
				4'd1: r20 <= regA_q;
				4'd2: r38 <= regA_q;
				4'd3: r50 <= regA_q;
				4'd4: r68 <= regA_q;
				4'd5: r80 <= regA_q;
				4'd6: r98 <= regA_q;
				4'd7: rb0 <= regA_q;
				4'd8: rc8 <= regA_q;
				4'd9: re0 <= regA_q;
				default: ;
			endcase
			if (ecnt == 4'd9) begin
				{cur, nxt, lfo, eg, env, tl, kon} <= st_q;
				{fmt, base, loop16, endn16} <= hdr_q;
				estate <= E_CACHE;
			end
		end

		E_CACHE: begin
			c_step <= step_full >> 2;
			c_tl   <= {r50[7:1], 10'd0};
			if (!pan[3]) begin
				c_panl <= (pan == 4'sd7) ? 10'h3ff : {pan[2:0], 5'd0};
				c_panr <= 10'd0;
			end else if (pan != -4'sd8) begin
				c_panl <= 10'd0;
				c_panr <= (pan == -4'sd7) ? 10'h3ff : {(3'd0 - pan[2:0]), 5'd0};
			end else begin
				c_panl <= 10'h3ff; c_panr <= 10'h3ff;
			end
			c_lfostep <= lfo_step_t;
			c_lme <= {loop16, 16'd0} - {endn16, 16'd0};
			c_am <= am_t;
			c_pm <= pm_t;
			c_ar <= effrate(r98[7:4], corr);
			if (r68[6]) begin
				c_dr <= 6'd48; c_sr <= 6'd63; c_rr <= 6'd63; c_sus <= 10'h080;
			end else begin
				c_dr <= effrate(r98[3:0], corr);
				c_sr <= effrate(rb0[3:0], corr);
				c_rr <= effrate(rc8[3:0], corr);
				c_sus <= {sl5, 5'd0};
			end
			estate <= E_PREP;
		end

		E_PREP: begin
			// order matters: wave load resets the envelope before key processing
			begin : prep
				reg [9:0]  env_p;
				reg [2:0]  eg_p;
				reg [17:0] lfo_p;
				reg [31:0] cur_p, nxt_p;
				reg        kon_p;
				env_p = env; eg_p = eg; lfo_p = lfo; cur_p = cur; nxt_p = nxt; kon_p = kon;
				if (env_reset[e_ch]) env_p = 10'h3ff;
				if (key_pend[e_ch]) begin
					kon_p = key_pend_on[e_ch];
					if (kon_p != kon) begin
						if (kon_p) begin
							if (eg_p != EG_ATTACK) begin
								eg_p = EG_ATTACK;
								if (r68[5]) lfo_p = 18'd0;
								if (c_ar == 6'd63) env_p = 10'd0;
								cur_p = 32'd0; nxt_p = 32'd0;
							end
						end else begin
							if (eg_p < EG_RELEASE) eg_p = EG_RELEASE;
						end
					end
				end
				env <= env_p; eg <= eg_p; lfo <= lfo_p; cur <= cur_p; nxt <= nxt_p; kon <= kon_p;
			end
			key_clr[e_ch] <= key_pend[e_ch];
			env_clr[e_ch] <= env_reset[e_ch];
			if (r50[0]) tl <= c_tl;
			estate <= E_CLK1;
		end

		E_CLK1: begin
			lfo <= lfo + c_lfostep;
			eg  <= eg1;
			case (eg1)
				EG_ATTACK:  rate <= c_ar;
				EG_DECAY:   rate <= c_dr;
				EG_SUSTAIN: rate <= c_sr;
				EG_RELEASE: rate <= c_rr;
				default:    rate <= 6'd5;
			endcase
			estate <= E_CLK1B;
		end

		E_CLK1B: begin
			inc_r    <= inc_val;
			fire_r   <= e_fire;
			pm_add_r <= (c_pm != 6'd0) ? pm_add : 32'd0;
			estate <= E_CLK1C;
		end

		E_CLK1C: begin
			nxt_a_r <= nxt + c_step + pm_add_r;
			estate <= E_CLK2;
		end

		E_CLK2: begin
			begin : clk2
				reg [9:0] env_n;
				env_n = env;
				if (fire_r) begin
					if (eg == EG_ATTACK)
						env_n = att_env[9:0];
					else begin
						env_n = dec_env[10] ? 10'h3ff : dec_env[9:0];
						if (env_n >= 10'h0c0 && eg < EG_REVERB && r38[3]) eg <= EG_REVERB;
					end
				end
				env <= env_n;
			end
			cur <= nxt;
			nxt <= nxt_b;
			if (tl != c_tl) begin
				if (tl < c_tl) tl <= (tl + 17'd19 > c_tl) ? c_tl : tl + 17'd19;
				else           tl <= (tl < c_tl + 17'd38) ? c_tl : tl - 17'd38;
			end
			estate <= E_FETCH;
			second <= 1'b0;
		end

		E_FETCH: begin
			envl0_r <= envl0;    // env/tl/lfo are stable here; used in E_VOL
			// first cycle: compute addresses and issue request
			if (!e_req && !second) begin
				if (env > 10'h200) estate <= E_WB;
				else begin
					case (fmt)
						2'd0: begin a_hi <= a8;  a_lo <= a8;  lo_kind <= 2'd0; e_addr <= a8;  end
						2'd2: begin a_hi <= a16; a_lo <= a16 + 1'd1; lo_kind <= 2'd1; e_addr <= a16; end
						default:
							if (!pos[0]) begin a_hi <= a12; a_lo <= a12 + 1'd1; lo_kind <= 2'd2; e_addr <= a12; end
							else begin a_hi <= a12 + 2'd2; a_lo <= a12 + 1'd1; lo_kind <= 2'd3; e_addr <= a12 + 2'd2; end
					endcase
					e_req <= 1'b1;
				end
			end else if (e_req && mem_ack) begin
				if (!second) begin
					b_hi <= a_hi[0] ? mem_rdata[15:8] : mem_rdata[7:0];
					if (lo_kind == 2'd0) begin
						e_req <= 1'b0;
						sample <= {a_hi[0] ? mem_rdata[15:8] : mem_rdata[7:0], 8'd0};
						estate <= E_VOL;
					end else if (a_hi[21:1] == a_lo[21:1]) begin
						e_req <= 1'b0;
						sample <= lo_sample(a_hi[0] ? mem_rdata[15:8] : mem_rdata[7:0],
						                    a_lo[0] ? mem_rdata[15:8] : mem_rdata[7:0], lo_kind);
						estate <= E_VOL;
					end else begin
						second <= 1'b1;
						e_addr <= a_lo;
					end
				end else begin
					e_req <= 1'b0;
					sample <= lo_sample(b_hi, a_lo[0] ? mem_rdata[15:8] : mem_rdata[7:0], lo_kind);
					estate <= E_VOL;
				end
			end
		end

		E_VOL: begin
			sh_l <= lenv[9:6];
			sh_r <= renv[9:6];
			estate <= E_VOL2;
		end

		E_VOL2: begin
			vol_r <= pow_q_r >> sh_r;
			mul_v <= pow_q_l >> sh_l;
			estate <= E_MULL;
		end

		E_MULL: begin
			prod_r <= mul_p;
			mul_v  <= vol_r;
			estate <= E_MULR;
		end

		E_MULR: begin
			if (r68[4]) acc2 <= acc2 + mul_sh; else acc0 <= acc0 + mul_sh;
			prod_r <= mul_p;
			estate <= E_MULR2;
		end

		E_MULR2: begin
			if (r68[4]) acc3 <= acc3 + mul_sh; else acc1 <= acc1 + mul_sh;
			estate <= E_WB;
		end

		E_WB: begin
			st_we    <= 1'b1;
			st_waddr <= e_ch;
			st_wdata <= {cur, nxt, lfo, eg, env, tl, kon};
			ecnt <= 4'd0;
			regA_raddr <= 8'h20 + e_ch + 1'd1;
			if (e_ch == 5'd23) begin
				mix_in <= acc0; mix_k <= mixscale(sc_l);
				estate <= E_MIX;
			end else begin
				e_ch <= e_ch + 1'd1;
				gap_cnt <= 8'd0;
				estate <= E_GAP;
			end
		end

		E_GAP: begin
			if (gap_cnt != 8'hff) gap_cnt <= gap_cnt + 1'd1;
			if (h_idle && ((fifo_cnt == 6'd0 && !pref_dirty) || gap_cnt >= 8'd200))
				estate <= E_RD;
		end

		// DO2 = (FM * mix_fm + PCM * mix_pcm) >> 11, as ymfm
		// (each product a clock later in mix_pr: a wait state after each new mix_in / mix_k)
		E_MIX: estate <= E_MIX0;

		E_MIX0: begin
			mix_r <= mix_pr;
			mix_in <= {{11{fm_hl[20]}}, fm_hl}; mix_k <= mixscale(fsc_l);
			estate <= E_MIXW1;
		end

		E_MIXW1: estate <= E_MIXA;

		E_MIXA: begin
			mix_r <= mix_r + mix_pr;
			mix_in <= acc1; mix_k <= mixscale(sc_r);
			estate <= E_MIXW2;
		end

		E_MIXW2: estate <= E_MIX2;

		E_MIX2: begin
			do2_l <= clamp16(mix_sh);
			mix_r <= mix_pr;
			mix_in <= {{11{fm_hr[20]}}, fm_hr}; mix_k <= mixscale(fsc_r);
			estate <= E_MIXW3;
		end

		E_MIXW3: estate <= E_MIXB;

		E_MIXB: begin
			mix_r <= mix_r + mix_pr;
			estate <= E_MIX3;
		end

		E_MIX3: begin
			do2_r <= clamp16(mix_sh);
			do1_l <= clamp16({{12{acc2[31]}}, acc2});
			do1_r <= clamp16({{12{acc3[31]}}, acc3});
			ld_dec <= 1'b1;
			e_ch <= 5'd0;
			estate <= E_IDLE;
		end

		default: estate <= E_IDLE;
	endcase
end

function signed [15:0] lo_sample;
	input [7:0] hi;
	input [7:0] lo;
	input [1:0] kind;
	case (kind)
		2'd1:    lo_sample = {hi, lo};
		2'd2:    lo_sample = {hi, lo[3:0], 4'd0};
		2'd3:    lo_sample = {hi, lo[7:4], 4'd0};
		default: lo_sample = {hi, 8'd0};
	endcase
endfunction

assign mem_req   = e_req | h_req;
assign mem_addr  = e_req ? e_addr : h_addr;
assign mem_we    = e_req ? 1'b0 : h_we;
assign mem_wdata = h_wdata;

endmodule
