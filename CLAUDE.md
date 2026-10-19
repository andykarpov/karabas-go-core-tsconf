# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

The TS-Conf ZX Spectrum core for the Karabas Go, Mini and Mini G boards: Xilinx Spartan-6 XC6SLX25, ISE 14.7 (XST). One core, three tops: `src/rtl/karabas_go_top.v` (VGA through the FT812 / video DAC, floppy connector), `karabas_mini_top.v` and `karabas_minig_top.v` (HDMI, the FT812 video on HDMI too). The machine is `src/rtl/tsconf.v` (TS-Conf of ZX Evolution with General Sound, Turbosound FM, SAA1099, OPL2, Covox, ZiFi / RS232 over USB, the FDC of the Go); the tops differ in their board glue and the defines HW_ID1 (Go), HW_ID2 (Mini), HW_ID2 + HW_ID3 (Mini G), set in the `.xst` files.

The board modules (MCU link, memories, clocks, DACs, OSD, HDMI) come from the git submodule `modules/` ([karabas-go-modules](https://github.com/andykarpov/karabas-go-modules), shared by the Karabas Go cores; clone with `--recursive` or run `git submodule update --init`). A change to them is made there and taken here by updating the submodule commit. Its `CLAUDE.md` and `docs/PLAN.md` have the rules (Verilog-2001 for XST, tests, checks of LUTs and timing). `src/rtl/fd1793` is another submodule, not used by the build (the FDC is `src/rtl/vg93`).

## Build

- `cd src && make` builds the three boards (`make go`, `mini`, `minig` one of them; `make minig-xst`, `-impl`, `-core` one step; `make minig-report` the utilization and timing of the last build, `make minig-coremode` the second timing run of the Mini / Mini G, see Timing). It runs the ISE command-line flow (the steps and options of the former ISE projects) and sources `/opt/Xilinx/14.7/ISE_DS/settings64.sh` (`ISE_SETTINGS=` to change it). The boards share `xst/` and `_ngo/` in `src/`, so they are built one after the other; a board takes 10 to 30 minutes, mostly PAR.
- Inputs per board: `karabas_<board>.prj` (the source list, add new files here; the shared modules as `"../modules/rtl/..."`), `.xst`, `.ucf`, `.ut`. There is no ISE GUI project (`.xise`) any more; the Makefile has its map / par options. The map cost table (the placement seed) is per board, `MAP_T_<board>` (the Mini 2, the others 1): when a build of the nearly full Mini / Mini G misses a constraint by a placement (a path without logic and a long route), try another (2...5) before changing the design.
- `core` packs `karabas_<board>.bin` and the ROMs of `core.json` (Go), `core_mini.json`, `core_minig.json` into `tsconf.kg1` / `kg2` / `kg3` with `make_core.py`, a symlink to karabas-go-tools (the sibling repo must be checked out next to this one). The `.bin` and `.kg*` files are committed as the release.
- The `osd` items of the json are the soft switch registers in their order (`kg_soft_switches` in the tops cut the fields out). A new item changes the index of the items after it.
- The Mini and Mini G are nearly full (96-97 % of the LUTs, 99-100 % of the slices; zhdmi takes about 900 LUTs more than the HDMI encoder the core had before). Check `karabas_<board>_map.mrp` and `karabas_<board>.par` after a change (and `karabas_<board>_core.twr` of the Mini / Mini G); `make <board>-report` prints them.

## Timing

- Clocks (the tops), one PLL (VCO 925 MHz), phase 0: clk_sys 84.09 MHz (SRAM controller, the SDRAM of the General Sound), clk_bus 28.03 MHz (the machine; clk_sys / 3, every edge of clk_bus is an edge of clk_sys; its PLL output has no BUFG in kg_pll, the BUFG is in the top and on the Mini / Mini G the same output feeds the BUFGMUXes of `hdmi_pll`), clk_8 7.97 MHz (the FDC of the Go; FT_CLK_OUT and DCM_CLKGEN of the Mini / Mini G), 12 MHz (MIDI). `rtl/bus_ce.v` makes ce_28m (the clk_sys enable before each clk_bus edge, for the SRAM controller) and v_clk (V_CLK of the Go).
- HDMI (`rtl/hdmi`): `hdmi_top.v` (the FT812 / core mux, the audio sample transfer, the crossings into the pixel clock) around zhdmi (`hdmi_tx` of modules). `hdmi_pll.v` measures FT_CLK and programs DCM_CLKGEN (8 MHz x M) for the FT modes; the pixel clock is one BUFGMUX of clk_bus (its PLL output) and the DCM. The 5x clock of the -2 part allows FT modes up to 64 MHz; 72 and 80 MHz are beyond the CLKFX limit.
- The crossings into the pixel clock: the FT812 video is taken at the falling FT_CLK (in the IOB) and goes through `kg_async_fifo` (same frequency, unknown phase), whose write side runs on the falling FT_CLK too (half a period of 80 MHz is shorter than the route from the IOB). What goes from clk_bus (the core video, ft_sel, audio_en, the reset of hdmi_tx, the audio sample) leaves registers on the falling clk_bus: in the mode of the core the BUFGMUX output is about 4 ns later than the BUFG of clk_bus. In the FT mode ft_sel / audio_en / the reset go through two flip-flops, the audio sample with a toggle.
- The ucf bounds clk_bus -> pixel clock as an asynchronous crossing (TS_BUS_TO_PIX), as it is in the FT mode; `make <board>-coremode` runs trce again with the FT-mode constraints taken out of the pcf (`src/pcf_core.py`), which checks the same paths with the setup and hold of clk_bus. Run it after every build of the Mini / Mini G. The BUFGMUX select has a TIG (a KEEP net `mux_sel`; INST TNM on a BUFGMUX is not supported).
- MCU_SCK of the Mini G goes through IBUFG + BUFG (on local routing PAR could not meet hold); the SCK of the FT812 SPI, not a clock load, takes the IBUFG output.
- The three ucf have the same timing block (the end of each file, then the parts of the board): PERIOD on CLK_50MHZ (derived onto the PLL outputs), TS_CLK_MCU, DATAPATHONLY bounds for the asynchronous crossings (MCU_SCK <-> clk_bus, clk_bus <-> clk_8 of the FDC, FT_CLK, ESP32 I2S), the SRAM budget (12 ns out + 10 ns tAA + 12 ns in in three clk_sys), the FT pixel clock with its own PERIOD (64 MHz), TS_BUS_TO_PIX and the bounds of the fifo (TS_FT_TO_PIX, TS_PIX_TO_FT) and of FT_CLK <-> clk_bus. Each exception is explained there; do not TIG paths that are real.
- No clocks from logic and no latches (check "Clock Information" of the `.syr`; the `volTable` of `ym2149.v` with a constant clock is a ROM, XST only reports it there): the registers on the Z80 clock in `zports.v` run on clk_bus with zpos, the IDE trigger latches are registers with a bypass, the SAA1099 runs on clk_bus with an 8 MHz enable, the /RAWREAD catcher of `vg93_read_path` runs on clk_8 (`SYNC_RAWREAD`). A register whose initial value differs from its asynchronous reset value makes XST build a latch (`video_ports.v`).

## Simulation

- `src/sim/run_eq_sim.sh` (iverilog, ISim): the rewrites of the timing work against the old code in `sim/ref` (the versions of cec5631, modules renamed `*_ref`): `tb_eq_zports`, `tb_eq_saa`, `tb_eq_rawread`, and `tb_bus_ce` (with the PLL model). Each prints `<tb>: 0 errors`.
- `src/sim/run_hdmi_sim.sh` (ISim): `tb_hdmi_top`, the core video at 28 MHz and the FT812 at 40 / 72 MHz through `hdmi_pll` and the fifo, every pixel where it enters `hdmi_tx`, the audio samples and their rate. zhdmi runs as a ghdl `--synth` netlist (ISim 14.7 stops in `zhdmi_island_encoder.vhd`).
- `src/sim/run_burst_sim.sh` (ISim): `tb_mcu_burst.vhd`, the CMD_CAPS answer and the rom loader over classic frames and bursts at 16 / 32 MHz, `kg_mcu` with the parameters of the tops.
- `src/sim/run_kbd_sim.sh` (ISim): `tb_kbd_rtc.vhd`, `kg_mcu` and `hid_parser` as in the tops: PS/2 scancodes from the MCU read by the CPU through the RTC registers F0..FF (the keyboard buffer of `usb_ps2_keybuf.v`, on after register 0C bit 7 = 0; Wild Commander and others read the keyboard so), the buffer reset, and a USB report on the key matrix.
- The tests of the shared modules are in `modules/sim` (`run_all.sh`).

## Layout

- `src/rtl/tsconf.v` and `src/rtl/tsconf/`: the TS-Conf machine (zclock, zports, zmem, dram, video, dma, ...); `tune.v` its defines.
- `src/rtl/karabas_*_top.v`: the boards: PLL, `bus_ce`, `kg_mcu`, `kg_soft_switches`, `kg_cursor`, `kg_osd_overlay`, the DACs, HDMI.
- `src/rtl/mcu`: the core-specific parts of the HID input (`hid_parser.vhd`, `usb_ps2_keybuf.v`), `dot_matrix.v` (Mini G).
- `src/rtl/sound`: GS (`gs_top.v`, SDRAM on clk_sys), Turbosound FM (jt12), SAA1099, OPL2 (jtopl), the mixer.
- `src/rtl/vg93`, `hrdy_fdc.v`: the FDC of the Go. `src/rtl/uart/zifi.vhd`: ZiFi and the RS232 ports (kg_fifo).
