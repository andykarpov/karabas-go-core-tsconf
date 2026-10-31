// Thanks to deathsoft for the transistor-level schematic of the chip and to dr.Titus for the gate-level RTL.
//
// 1818VG93 (WD FD1793) - synchronous behavioural model.
//
// The pins of the chip plus SYSCLK from the oscillator of CLK and RCLK, at least 8 x the highest CLK (16 MHz for a
// 1 / 2 MHz CLK; an RCLK half period of 125 ns must hold a SYSCLK edge). CLK must be a square wave: the WD pulse
// length is the CLK low phase (see the CLK port). CLK and RCLK edges are events, each handled in one SYSCLK cycle,
// so CLK may change its frequency (turbo boards switch it between 1 and 2 MHz). vg93_timing
// tells the blocks when a microword ends, when its second half runs and when a bit cell of the disk ends; the
// microcode store (vg93_urom) is a ROM in block RAM. Behaviour and event order follow the C core src/vg93.c and the
// gate-level reference ref/rtl/schematic; docs/behav_map.md maps every name here to both.
//
// WD timing: a WD pulse is the CLK low phase (MFM; FM: one CLK period) as seen through the SYSCLK samples - its
// length is exact when CLK is divided from SYSCLK, +-1 SYSCLK period when CLK is asynchronous to SYSCLK; it starts
// 1..2 SYSCLK periods after the CLK edge (2 with CLK divided from SYSCLK). WD is combinational: register it before an
// FPGA pin (one more SYSCLK of delay), else its glitches at the SYSCLK edges are extra flux transitions for a drive.
//
// Build macros (all optional; none set = the chip, identical at the pins and in the microword trace to the
// gate-level schematic). Set in code by vg93_config.vh (a variant supplies its own), or by the project / +define:
//   VG93_ROM_FILE  path of the microcode ROM image (default "vg93-microcode-rom.hex")
//   VG93_EMBEDDED  the model inside a larger FPGA design: DRQ, INTRQ and /VFOE push-pull (active high DRQ / INTRQ,
//                  WF_n_VFOE_n = /VFOE, the /WF input unused) instead of open drain
//   VG93_FD1793_MARKS  A1h / C2h sync marks as on the WD FD1793: channel bit 13 compared too (by default the VG93
//                  die defect is kept: bit 13 ignored, 0x6489 / 0x7224 sync like A1h / C2h; protections rely on it)
// Cuts for small devices (the pin is gone from the port list; the rest behaves as the chip with that pin tied):
//   VG93_MFM_ONLY  no DDEN_n: MFM only, DDEN_S constant 1 (as DDEN_n tied low; the synthesis drops the FM logic -
//                  FM mark detectors, FM write pipelines, the FM cell phases)
//   VG93_NO_TEST   no TEST_n: the step rate is always counted (TEST_n high)
//   VG93_NO_RG     no RG output (the read gate logic is dropped)
//   VG93_NO_PIN33  no WF_n_VFOE_n: no /WF input (no write fault vector) and no /VFOE output (pin 33 pulled up and the
//                  own /VFOE not seen back; a Beta Disk board leaves pin 33 open)
//   VG93_TURBO_STEP  the step rate (and the delays counted in step ticks: head settle, head load) as with CLK 2 MHz
//                  while CLK stays 1 MHz - the turbo boards' faster seek without the 2 MHz core (vg93_drive)
//   VG93_FAST_SYSCLK  for SYSCLK >= 40 MHz (at 16 MHz keep the default). Two input stages that make the default
//                  exact at any SYSCLK are left out; each moves an event by at most one SYSCLK period:
//                  - /RAWREAD without the asynchronous catcher (vg93_read_path): only the SYSCLK-sampled level is
//                    used. A pulse shorter than one SYSCLK period can be missed (16 MHz: < 62.5 ns, 50 MHz: < 20 ns;
//                    drive / separator pulses are typically >= 100 ns, some separators give 50..125 ns). The half
//                    cell (RCLK level) of a pulse is taken at its first SYSCLK sample instead of at its edge: a pulse
//                    that starts less than one SYSCLK period before an RCLK edge counts in the next half cell only
//                    (a window of 62.5 ns of a 500 ns half cell at 16 MHz, 20 ns at 50 MHz: a pulse at the edge of
//                    the separator window, where the read is marginal anyway). The posedge /RAWREAD clock domain
//                    disappears: one SYSCLK domain.
//                  - REG_DAL_IN loaded from the DAL pins directly (vg93_host_bus, no DAL copy register): it takes
//                    the same sample (DAL at the last SYSCLK edge with /WE and /CS low), one SYSCLK period earlier,
//                    with the unsampled /WE & /CS as the load enable. Visible only when a host write overlaps the
//                    one-word enable of the previous write to the same register (the new byte arrives one SYSCLK
//                    earlier); DAL must be stable at the SYSCLK edges around the rise of /WE, as in the default.
//                  Everything else (word and cell timing, WD, the microword trace) is as in the default build.
// The model holds no simulation code: the microword trace (VG93_UTRACE), the event model checks (VG93_CHECKS) and
// the pull-ups of open inputs belong to the testbench (rtl/tb/utrace_behav.vh, behav_checks.vh, vg93_tb_common.vh),
// which reads the blocks by hierarchical names.
// The MAX II build (rtl_epm570: microcode in the UFM) sets all five cuts and replaces vg93_urom, vg93_ucode.vh and
// vg93_dcnt with its own files (rtl_epm570/README.md).
//
// The blocks:
//   vg93_timing        CLK / RCLK -> word end, second half of a word, cell end; read mode, MR_S, DDEN_S
//   vg93_decoder       the microword -> named actions
//   vg93_sequencer     PC, jump condition, skip; life of a command
//   vg93_urom          microcode store: ROM in block RAM (the word at the new PC from each word end on)
//   vg93_task_regs     OP, TRK, SEC, serial incrementer and comparator
//   vg93_data_channel  DATA, DATA_SHIFT, DRQ / LOST, FORMAT special bytes
//   vg93_counters      CNT1, CNT2, ID field counter, byte strobe
//   vg93_dcnt          down counter with load and shift: CNT1, CNT2, step rate
//   vg93_drive         READY / TR00 / IP / HLT inputs, step rate, STEP, DIRC, TG43, HLD
//   vg93_status        TYPE1, status flags and register, INTRQ
//   vg93_read_path     bit cell sampler, mark detectors, MFM decoder, RG, /VFOE
//   vg93_crc           CRC-16
//   vg93_write_path    encoder, WG, WD, precompensation
//   vg93_host_bus      host bus
//
// Names (one rule for all blocks):
//   x          a register as the last microword ended: what the microword works on
//   x_next     the value the current microword forms
//   x_seen     what the host and the pins see: x_next from the second half of the word on, else x
//   x_live     an RS latch now (its register plus the current set / reset terms); x_held its register
//   x_cell     the value with the cell that ends in this cycle (a word ending together with a cell sees it)
//   x_d        one microword earlier; x_prev one SYSCLK cycle earlier
//   x_q        a pin sampled by SYSCLK (active high); x_pin a pin straight, not sampled (active high)
//   x_n        active low
// Schematic names (U123, q257, F1 / F2, REG_*) appear in comments only, as cross references.
`include "vg93_config.vh"
module vg93_top (
    input  wire SYSCLK,         // system clock, >= 8 x CLK, from the oscillator of CLK and RCLK
    // CLK: controller clock, 1 MHz (2 MHz on turbo boards). IMPORTANT: it must be a square wave (50 % duty). As on
    // the chip, the MFM write window is the CLK low phase: a WD pulse lasts exactly as long as CLK is low (500 ns at
    // 1 MHz; a 30 / 70 % CLK gives 300 or 700 ns). FM: one CLK period (1 us), any duty. With SYSCLK from another
    // oscillator the WD length is also rounded to SYSCLK periods (+-62 ns at 16 MHz).
    input  wire CLK,
    input  wire MR_n,           // master reset, active low
    // host bus
    input  wire CS_n,           // chip select, active low
    input  wire RE_n,           // read enable, active low
    input  wire WE_n,           // write enable, active low
    input  wire [1:0] A,        // register: 0 status / command, 1 track, 2 sector, 3 data
    inout  wire [7:0] DAL,      // data bus, true polarity (FD1793)
    output wire DRQ,            // data request, active high, open drain
    output wire INTRQ,          // interrupt request, active high, open drain
    // drive
    output wire STEP,           // step pulse, active high
    output wire DIRC,           // direction: 1 = step in
    output wire EARLY,          // write precompensation: write early, active high
    output wire LATE,           // write precompensation: write late, active high
    output wire HLD,            // head load, active high
    output wire TG43,           // track greater than 43, active high
    output wire WG,             // write gate, active high
    output wire WD,             // write data pulses, active high; combinational (as on the chip): register it before
                                // an FPGA pin, its glitches at the SYSCLK edges are real pulses for a drive
`ifndef VG93_NO_RG
    output wire RG,             // read gate (data separator sync), active high
`endif
    input  wire RCLK,           // read clock from the data separator
    input  wire RAWREAD_n,      // raw read pulses from the drive, active low
    input  wire READY,          // drive ready, active high
    input  wire TR00_n,         // track 00, active low
    input  wire IP_n,           // index pulse, active low
    input  wire WPRT_n,         // write protect, active low
`ifndef VG93_NO_PIN33
    inout  wire WF_n_VFOE_n,    // input /WF (write fault), output /VFOE (separator enable, open drain); active low
`endif
    input  wire HLT             // head load timing (head engaged), active high
`ifndef VG93_NO_TEST
   ,input  wire TEST_n          // test (no step rate delay), active low
`endif
`ifndef VG93_MFM_ONLY
   ,input  wire DDEN_n          // double density: 0 = MFM, 1 = FM
`endif
);
    // ---- pins ----
    // SYSCLK comes from the oscillator of CLK and RCLK, so the pins are sampled once (vg93_timing: one cycle later
    // the event is handled). /RAWREAD (from the drive) and the host bus are asynchronous; /RAWREAD pulses are caught
    // in the read path (not with VG93_FAST_SYSCLK).
    reg  clk_q = 1'b0, rclk_q = 1'b1;
    reg  mr_q = 1'b0, hlt_q = 1'b0, ip_q = 1'b0, ready_q = 1'b0, tr00_q = 1'b0;
    reg  wprt_q = 1'b0, wr_q = 1'b0, rd_q = 1'b0, rawread_q = 1'b0;
    reg  [1:0] addr_q = 2'd0;
    always @(posedge SYSCLK) begin
        {clk_q, rclk_q} <= {CLK, RCLK};
        {mr_q, hlt_q, ip_q, ready_q, tr00_q, wprt_q} <= {!MR_n, HLT, !IP_n, READY, !TR00_n, !WPRT_n};
        {wr_q, rd_q, addr_q} <= {!CS_n && !WE_n, !CS_n && !RE_n, A};   // /CS combined before the sample
        rawread_q <= !RAWREAD_n;
    end
`ifndef VG93_FAST_SYSCLK
    reg  [7:0] dal_q = 8'd0;
    always @(posedge SYSCLK) dal_q <= DAL;
`endif
`ifdef VG93_MFM_ONLY
    wire dden_q = 1'b1;                   // no DDEN_n: MFM (vg93_timing keeps DDEN_S at 1)
`else
    reg  dden_q = 1'b0;
    always @(posedge SYSCLK) dden_q <= !DDEN_n;
`endif
`ifdef VG93_NO_TEST
    wire test_q = 1'b0;                   // no TEST_n: the step rate always counts
`else
    reg  test_q = 1'b0;
    always @(posedge SYSCLK) test_q <= !TEST_n;
`endif
    wire cs_pin = !CS_n, re_pin = !RE_n, rawread_pin = !RAWREAD_n;   // straight from the pins, active high

    // ---- from vg93_timing ----
    wire cell_ends, word_ends, power_on, second_half, second_half_held, write_window, cell_window;
    wire mr_s, mr_next, mfm, read_request;
    // ---- from vg93_decoder ----
    wire [7:0] jump_addr;                                                              // -> sequencer
    wire [3:0] test_sel;
    wire [2:0] test_op_bit, stay_sel;
    wire [1:0] skip_sel;
    wire jump_lo, jump_hi, int_vector_en, jump_always;
    wire set_type1, clr_type1, clr_busy, set_crc_error, clr_crc_error, set_rnf;         // -> status
    wire set_write_fault, set_write_prot, int_word;
    wire set_hld, clr_hld, step_pulse, set_dirc, clr_dirc, dirc_from_cmp, tg43_from_cmp;  // -> drive
    wire set_rg, clr_rg, det_a1_en, det_fm_mark_en, det_trans_en, det_read_am_en;      // -> read path
    wire [3:0] cnt_preset;                                                             // -> counters
    wire cnt1_load, cnt2_load, cnt1_dec, cnt1_shift_len, cnt2_dec_on_byte, cnt2_dec_on_step, cnt1_dec_on_index;
    wire id_count, id_capture, byte_sync, byte_sync_on_mark, byte_sync_on_mark_mfm, byte_sync_on_preamble;
    wire [1:0] trk_fill, sec_fill, cmp_operand;                                        // -> task registers
    wire trk_shift, sec_shift, ser_inc_force_up, cmp_en;
    wire read_byte_word, write_byte_word, format_word, set_lost;                       // -> data channel
    wire crc_preset_ffff, crc_preset_a1, crc_preset_fm_trans;                          // -> CRC
    wire [1:0] write_src;                                                              // -> write path
    wire clock_drop;
    wire read_enable, write_gate, set_busy, ser_inc;                                   // shared
    // ---- from vg93_sequencer ----
    wire [7:0] pc;
    wire [18:0] mword;
    wire fetching;
    // ---- from vg93_task_regs ----
    wire [7:0] cmd_reg, track_seen, sector_seen;
    wire [3:0] int_conditions;
    wire host_int_cmd, cmp_differ, cmp_greater;
    // ---- from vg93_data_channel ----
    wire [7:0] data_seen;
    wire shift_msb, drq, write_ready, lost_seen, write_drq_off;
    wire format_f7, format_fm_mark, index_mark, load_a1, load_c2;
    // ---- from vg93_counters ----
    wire cnt1_zero, cnt2_zero, id_nonzero, byte_stb, ser_inc_sync;
    // ---- from vg93_drive ----
    wire ready, tr00, ready_seen, tr00_seen, ip_seen, ready_rose, ready_fell, ip_edge, step_tick;
    wire step_out, dirc, tg43, hld_pin, head_loaded;
    // ---- from vg93_status ----
    wire [7:0] status_byte;
    wire type1, intrq;
    // ---- from vg93_read_path ----
    wire clock_cell, dec_data_cell, preamble, any_mark, rd_data, rg_pin, vfoe_seen;
    // ---- from vg93_crc ----
    wire crc_msb, crc_nonzero;
    // ---- from vg93_write_path ----
    wire write_bit, wg, wd, early, late;
    // ---- from vg93_host_bus ----
    wire [7:0] dal_in, dal_out;
    wire dal_oe, bus_cmd, bus_data, bus_data_read, wr_cmd_en, wr_trk_en, wr_sec_en, wr_data_en;
    // ---- pin 33 as the chip sees it: external /WF, or its own /VFOE (in a simulation the open drain already pulls
    // the pin low; an FPGA pin may not read back its own output) ----
`ifdef VG93_NO_PIN33
    wire pin33_low = 1'b0;                // no pin 33: no write fault vector, no /VFOE
`else
    wire pin33_low = !WF_n_VFOE_n || vfoe_seen;
`endif

    vg93_timing timing (
        .sysclk(SYSCLK), .clk_q(clk_q), .rclk_q(rclk_q), .mr_q(mr_q), .dden_q(dden_q),
        .read_enable(read_enable), .clock_cell(clock_cell),
        .cell_ends(cell_ends), .word_ends(word_ends), .power_on(power_on), .second_half(second_half),
        .second_half_held(second_half_held), .write_window(write_window), .cell_window(cell_window),
        .mr_s(mr_s), .mr_next(mr_next), .read_request(read_request), .mfm(mfm));

    vg93_decoder decoder (
        .mword(mword), .fetching(fetching), .pc(pc), .read_request(read_request),
        .jump_addr(jump_addr), .jump_lo(jump_lo), .jump_hi(jump_hi), .int_vector_en(int_vector_en),
        .jump_always(jump_always), .test_sel(test_sel), .test_op_bit(test_op_bit), .stay_sel(stay_sel),
        .skip_sel(skip_sel),
        .set_type1(set_type1), .clr_type1(clr_type1), .clr_busy(clr_busy), .set_crc_error(set_crc_error),
        .clr_crc_error(clr_crc_error), .set_rnf(set_rnf), .set_write_fault(set_write_fault),
        .set_write_prot(set_write_prot), .int_word(int_word),
        .set_hld(set_hld), .clr_hld(clr_hld), .step_pulse(step_pulse), .set_dirc(set_dirc), .clr_dirc(clr_dirc),
        .dirc_from_cmp(dirc_from_cmp), .tg43_from_cmp(tg43_from_cmp),
        .set_rg(set_rg), .clr_rg(clr_rg), .det_a1_en(det_a1_en), .det_fm_mark_en(det_fm_mark_en),
        .det_trans_en(det_trans_en), .det_read_am_en(det_read_am_en),
        .cnt1_load(cnt1_load), .cnt2_load(cnt2_load), .cnt_preset(cnt_preset), .cnt1_dec(cnt1_dec),
        .cnt1_shift_len(cnt1_shift_len), .cnt2_dec_on_byte(cnt2_dec_on_byte), .cnt2_dec_on_step(cnt2_dec_on_step),
        .cnt1_dec_on_index(cnt1_dec_on_index), .id_count(id_count), .id_capture(id_capture),
        .byte_sync(byte_sync), .byte_sync_on_mark(byte_sync_on_mark), .byte_sync_on_mark_mfm(byte_sync_on_mark_mfm),
        .byte_sync_on_preamble(byte_sync_on_preamble),
        .trk_shift(trk_shift), .sec_shift(sec_shift), .trk_fill(trk_fill), .sec_fill(sec_fill),
        .ser_inc_force_up(ser_inc_force_up), .cmp_en(cmp_en), .cmp_operand(cmp_operand),
        .read_byte_word(read_byte_word), .write_byte_word(write_byte_word), .format_word(format_word),
        .set_lost(set_lost),
        .crc_preset_ffff(crc_preset_ffff), .crc_preset_a1(crc_preset_a1), .crc_preset_fm_trans(crc_preset_fm_trans),
        .clock_drop(clock_drop), .write_src(write_src),
        .read_enable(read_enable), .write_gate(write_gate), .set_busy(set_busy), .ser_inc(ser_inc));

    vg93_sequencer sequencer (
        .sysclk(SYSCLK), .word_ends(word_ends), .power_on(power_on), .second_half(second_half),
        .second_half_held(second_half_held),
        .jump_addr(jump_addr), .jump_lo(jump_lo), .jump_hi(jump_hi), .int_vector_en(int_vector_en),
        .jump_always(jump_always), .write_gate(write_gate), .test_sel(test_sel), .test_op_bit(test_op_bit),
        .stay_sel(stay_sel), .skip_sel(skip_sel),
        .cmd_reg(cmd_reg), .host_int_cmd(host_int_cmd), .mr_s(mr_s), .mfm(mfm), .pin33_low(pin33_low),
        .ready(ready), .tr00(tr00), .dirc(dirc), .wprt_q(wprt_q), .head_loaded(head_loaded),
        .rd_data(rd_data), .write_drq_off(write_drq_off), .id_nonzero(id_nonzero), .byte_stb(byte_stb),
        .cmp_differ(cmp_differ), .crc_nonzero(crc_nonzero), .cnt1_zero(cnt1_zero), .cnt2_zero(cnt2_zero),
        .preamble(preamble), .ip_edge(ip_edge), .any_mark(any_mark), .format_f7(format_f7), .wr_cmd_en(wr_cmd_en),
        .pc(pc), .mword(mword), .fetching(fetching));

    vg93_task_regs task_regs (
        .sysclk(SYSCLK), .word_ends(word_ends), .second_half(second_half), .mr_s(mr_s), .mr_next(mr_next),
        .trk_shift(trk_shift), .sec_shift(sec_shift), .trk_fill(trk_fill), .sec_fill(sec_fill), .ser_inc(ser_inc),
        .ser_inc_force_up(ser_inc_force_up), .cmp_en(cmp_en), .cmp_operand(cmp_operand),
        .dal_in(dal_in), .wr_cmd_en(wr_cmd_en), .wr_trk_en(wr_trk_en), .wr_sec_en(wr_sec_en),
        .byte_stb(byte_stb), .ser_inc_sync(ser_inc_sync), .rd_data(rd_data), .shift_msb(shift_msb), .dirc(dirc),
        .cmd_reg(cmd_reg), .host_int_cmd(host_int_cmd), .int_conditions(int_conditions),
        .track_seen(track_seen), .sector_seen(sector_seen), .cmp_differ(cmp_differ), .cmp_greater(cmp_greater));

    vg93_data_channel data_channel (
        .sysclk(SYSCLK), .word_ends(word_ends), .second_half(second_half),
        .read_byte_word(read_byte_word), .write_byte_word(write_byte_word), .format_word(format_word),
        .set_busy(set_busy), .set_lost(set_lost),
        .byte_stb(byte_stb), .type1(type1), .mfm(mfm), .cnt1_zero(cnt1_zero), .cnt2_zero(cnt2_zero),
        .dec_data_cell(dec_data_cell),
        .dal_in(dal_in), .wr_data_en(wr_data_en), .bus_data(bus_data), .bus_data_read(bus_data_read),
        .data_seen(data_seen), .shift_msb(shift_msb), .drq(drq), .write_ready(write_ready), .lost_seen(lost_seen),
        .write_drq_off(write_drq_off),
        .format_f7(format_f7), .format_fm_mark(format_fm_mark), .index_mark(index_mark), .load_a1(load_a1),
        .load_c2(load_c2));

    vg93_counters counters (
        .sysclk(SYSCLK), .word_ends(word_ends),
        .cnt1_load(cnt1_load), .cnt2_load(cnt2_load), .cnt_preset(cnt_preset), .cnt1_dec(cnt1_dec),
        .cnt1_dec_on_index(cnt1_dec_on_index), .cnt1_shift_len(cnt1_shift_len), .cnt2_dec_on_byte(cnt2_dec_on_byte),
        .cnt2_dec_on_step(cnt2_dec_on_step), .id_capture(id_capture), .id_count(id_count),
        .byte_sync(byte_sync), .byte_sync_on_mark(byte_sync_on_mark), .byte_sync_on_mark_mfm(byte_sync_on_mark_mfm),
        .byte_sync_on_preamble(byte_sync_on_preamble), .ser_inc(ser_inc),
        .ip_edge(ip_edge), .step_tick(step_tick), .rd_data(rd_data), .mfm(mfm), .any_mark(any_mark),
        .preamble(preamble),
        .cnt1_zero(cnt1_zero), .cnt2_zero(cnt2_zero), .id_nonzero(id_nonzero), .byte_stb(byte_stb),
        .ser_inc_sync(ser_inc_sync));

    vg93_drive drive (
        .sysclk(SYSCLK), .word_ends(word_ends), .second_half(second_half), .mr_s(mr_s), .mr_next(mr_next),
        .mfm(mfm), .ready_q(ready_q), .tr00_q(tr00_q), .ip_q(ip_q), .hlt_q(hlt_q), .test_q(test_q),
        .step_pulse(step_pulse), .set_dirc(set_dirc), .clr_dirc(clr_dirc), .dirc_from_cmp(dirc_from_cmp),
        .tg43_from_cmp(tg43_from_cmp), .set_hld(set_hld), .clr_hld(clr_hld), .cmp_greater(cmp_greater),
        .ready(ready), .tr00(tr00), .ready_seen(ready_seen), .tr00_seen(tr00_seen), .ip_seen(ip_seen),
        .ready_rose(ready_rose), .ready_fell(ready_fell), .ip_edge(ip_edge), .step_tick(step_tick),
        .step_out(step_out), .dirc(dirc), .tg43(tg43), .hld_pin(hld_pin), .head_loaded(head_loaded));

    vg93_status status (
        .sysclk(SYSCLK), .word_ends(word_ends), .second_half(second_half), .second_half_held(second_half_held),
        .mr_s(mr_s), .set_type1(set_type1), .clr_type1(clr_type1), .set_busy(set_busy), .clr_busy(clr_busy),
        .set_crc_error(set_crc_error), .clr_crc_error(clr_crc_error), .set_rnf(set_rnf),
        .set_write_fault(set_write_fault), .set_write_prot(set_write_prot), .int_word(int_word),
        .host_int_cmd(host_int_cmd), .int_conditions(int_conditions), .ip_edge(ip_edge), .ready_rose(ready_rose),
        .ready_fell(ready_fell), .bus_cmd(bus_cmd), .ready_seen(ready_seen), .tr00_seen(tr00_seen),
        .ip_seen(ip_seen), .wprt_q(wprt_q), .head_loaded(head_loaded), .lost_seen(lost_seen), .drq(drq),
        .type1(type1), .intrq(intrq), .status_byte(status_byte));

    vg93_read_path read_path (
        .sysclk(SYSCLK), .cell_ends(cell_ends), .word_ends(word_ends), .second_half(second_half),
        .cell_window(cell_window), .mfm(mfm), .mr_s(mr_s), .mr_next(mr_next), .rclk_q(rclk_q),
        .rawread_pin(rawread_pin), .rclk_pin(RCLK), .rawread_q(rawread_q), .read_enable(read_enable),
        .det_a1_en(det_a1_en),
        .det_fm_mark_en(det_fm_mark_en), .det_trans_en(det_trans_en), .det_read_am_en(det_read_am_en),
        .set_rg(set_rg), .clr_rg(clr_rg),
        .clock_cell(clock_cell), .dec_data_cell(dec_data_cell), .preamble(preamble), .any_mark(any_mark),
        .rd_data(rd_data), .rg_pin(rg_pin), .vfoe_seen(vfoe_seen));

    vg93_crc crc (
        .sysclk(SYSCLK), .word_ends(word_ends), .mfm(mfm), .crc_preset_ffff(crc_preset_ffff),
        .crc_preset_a1(crc_preset_a1), .crc_preset_fm_trans(crc_preset_fm_trans), .read_enable(read_enable),
        .rd_data(rd_data), .write_bit(write_bit), .load_a1(load_a1), .format_fm_mark(format_fm_mark),
        .crc_msb(crc_msb), .crc_nonzero(crc_nonzero));

    vg93_write_path write_path (
        .sysclk(SYSCLK), .cell_ends(cell_ends), .word_ends(word_ends), .write_window(write_window), .mfm(mfm),
        .write_gate(write_gate), .clock_drop(clock_drop), .write_src(write_src),
        .index_mark(index_mark), .format_fm_mark(format_fm_mark), .load_a1(load_a1), .load_c2(load_c2),
        .shift_msb(shift_msb), .crc_msb(crc_msb),
        .write_bit(write_bit), .wg(wg), .wd(wd), .early(early), .late(late));

    vg93_host_bus host_bus (
        .sysclk(SYSCLK), .word_ends(word_ends), .cs_pin(cs_pin), .re_pin(re_pin), .addr_pin(A),
        .wr_q(wr_q), .rd_q(rd_q), .addr_q(addr_q),
`ifdef VG93_FAST_SYSCLK
        .wr_pin(!CS_n && !WE_n), .dal_pin(DAL),
`else
        .dal_q(dal_q),
`endif
        .status_byte(status_byte), .track_seen(track_seen), .sector_seen(sector_seen), .data_seen(data_seen),
        .dal_in(dal_in), .dal_out(dal_out), .dal_oe(dal_oe), .bus_cmd(bus_cmd), .bus_data(bus_data),
        .bus_data_read(bus_data_read), .wr_cmd_en(wr_cmd_en), .wr_trk_en(wr_trk_en), .wr_sec_en(wr_sec_en),
        .wr_data_en(wr_data_en));

    // ---- output pins ----
    assign DAL   = dal_oe ? dal_out : 8'bz;
    assign STEP  = step_out;
    assign DIRC  = dirc;
    assign EARLY = early;
    assign LATE  = late;
`ifndef VG93_NO_RG
    assign RG    = rg_pin;
`endif
    assign HLD   = hld_pin;
    assign TG43  = tg43;
    assign WG    = wg;
    assign WD    = wd;
`ifdef VG93_EMBEDDED
    assign DRQ   = drq;
    assign INTRQ = intrq;
`ifndef VG93_NO_PIN33
    assign WF_n_VFOE_n = !vfoe_seen;
`endif
`else
    assign DRQ   = drq ? 1'bz : 1'b0;               // open drain
    assign INTRQ = intrq ? 1'bz : 1'b0;             // open drain
`ifndef VG93_NO_PIN33
    assign WF_n_VFOE_n = vfoe_seen ? 1'b0 : 1'bz;   // open drain: /VFOE
`endif
`endif
endmodule
