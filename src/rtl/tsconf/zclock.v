// PentEvo project (c) NedoPC 2008-2011
//
// Z80 clocking module, also contains some wait-stating when 14MHz
//
// IDEAL:
// clk    _/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\_/`\
//          |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |
// zclk     /```\___/```\___/```\___/```````\_______/```````\_______/```````````````\_______________/```````````````\_______________/`
//          |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |
// zpos     `\___/```\___/```\___/```\___________/```\___________/```\___________________________/```\___________________________/```\
//          |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |   |
// zneg     _/```\___/```\___/```\_______/```\___________/```\___________________/```\___________________________/```\________________

// clock phasing:
// c3 must be zpos for 7mhz, therefore c1 - zneg
// for 3.5 mhz, c3 is both zpos and zneg (alternating)


// 14MHz rulez:
// 1. do variable stalls for memory access.
// 2. do fallback on 7mhz for external IO accesses
// 3. clock switch 14-7-3.5 only at RFSH

`include "../tune.v"

module zclock
(
  input             clk,
  output reg        zclk_out = 0,   // generated Z80 clock, passed through inverter externally
  input             c0, c2,

  input wire        iorq_s,
  input wire        external_port,

  output reg        zpos,
  output reg        zneg,

// stall enables and triggers
  input  wire       cpu_stall,
  input  wire       ide_stall,
  input  wire       dos_on,
  input  wire       vdos_off,

`ifdef PENT_312
  input  wire       boost_start,
  input  wire [4:0] hcnt,
  input  wire       upper8,
`endif

  input [1:0]       turbo   // 2'b00 -  3.5 MHz
                            // 2'b01 -  7.0 MHz
                            // 2'b1x - 14.0 MHz
);

`ifdef PENT_312
// Turbo-boost for Pentagon 71680 tacts emulation with 312 video lines
  wire [1:0] turbo_int = (turbo == 2'b00) ? (t_boost ? 2'b01 : 2'b00) : turbo;
  reg t_boost = 0;
  reg [4:0] hcnt_r = 0;
  always @(posedge clk)
    if (boost_start && !t_boost)
    begin
      t_boost <= 1'b1;
      hcnt_r <= hcnt;
    end
    else if (t_boost && !upper8 && (hcnt_r == hcnt))
      t_boost <= 1'b0;
`else
  wire [1:0] turbo_int = turbo;
`endif

// wait generator
  reg [3:0] stall_count = 0;

  wire dos_stall = dos_on || vdos_off;
  wire io_stall = iorq_s && external_port && turbo_int[1];
  wire stall_start = dos_stall || io_stall;
  wire stall_count_end = stall_count[3];
  wire dos_io_stall = stall_start || !stall_count_end;

  always @(posedge clk)
    if (stall_start)
    begin
      if (dos_stall)
        stall_count <= 4'd4;  // 4 tacts 28MHz (1 tact 7MHz)
      else if (io_stall)
        stall_count <= 4'd0;  // 8 tacts 28MHz (1 tact 3.5MHz)
    end
    else if (!stall_count_end)
      stall_count <= stall_count + 3'd1;

// Z80 clocking pre-strobes
  reg clk14_src = 0;  // source for 14MHz clock
  reg c2_cnt = 0;

  wire stall = cpu_stall || dos_io_stall || ide_stall;

  wire pre_zpos_140 = clk14_src;
  wire pre_zneg_140 = ~clk14_src;

  wire pre_zpos_70 = c2;
  wire pre_zneg_70 = c0;

  wire pre_zpos_35 = c2_cnt && c2;
  wire pre_zneg_35 = !c2_cnt && c2;

  wire pre_zpos = turbo_int[1] ? pre_zpos_140 : (turbo_int[0] ? pre_zpos_70 : pre_zpos_35);
  wire pre_zneg = turbo_int[1] ? pre_zneg_140 : (turbo_int[0] ? pre_zneg_70 : pre_zneg_35);

  always @(posedge clk)
  if (!stall)
    clk14_src <= ~clk14_src;

  always @(posedge clk) if (c2)
    c2_cnt <= ~c2_cnt;

// Z80 clocking strobes
  always @(posedge clk)
  begin
    zpos <= !stall && pre_zpos && zclk_out;
    zneg <= !stall && pre_zneg && !zclk_out;
  end

  // make Z80 clock: account for external inversion and make some leading of clock
  // 9.5 ns propagation delay: from clk posedge to zclk returned back any edge
  // (1/28)/2=17.9ns half a clock lead
  // 2.6ns lag because of non-output register emitting of zclk_out
  // total: 5.8 ns lead of any edge of zclk relative to posedge of clk => ACCOUNT FOR THIS WHEN DOING INTER-CLOCK DATA TRANSFERS

  // Z80 clocking
  always @(negedge clk)
  begin
    if (zpos)
      zclk_out <= 1'b0;

    if (zneg)
      zclk_out <= 1'b1;
  end

endmodule
