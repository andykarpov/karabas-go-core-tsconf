#!/usr/bin/env python3
"""Makes rtl/karabas_go_top.v from rtl/karabas_minig_top.v (MCU link v2): the machine, kg_mcu2, the
OSD (kg_l2_osd_overlay) and the keyboard are those of Mini G; the header and ports come from the last
v1 Go top (V1_REF), the board glue is that of the Go:
- no HDMI, no FT_CLK_OUT, no PCM1808 ADC, no ESP32 PCM: the FPGA and the FT812 share the video DAC
  (VGA_*, V_CLK of bus_ce or FT_CLK; FT_OE_N), the FT812 when the core (vdac2_sel) or the firmware
  (FT_VGA_ON) asks for it;
- MCU_SCK straight (not on a clock pin), INT of link v2 on MCU_SPI_IO[0] (N9), the FT812 select on
  MCU_SPI_FT_CS_N;
- the floppy connector of tsconf (the physical drive), the beeper, MIDI_CLK 12 MHz, DAC_LRCK / DAC_MUTE.
Every replacement must match once, else this stops. Run in src/: python3 tools/mktop_go.py
"""
import os
import subprocess
import sys

SRC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
V1_REF = "b589ea0"  # master before link v2


def sub(s, old, new, what):
    if s.count(old) != 1:
        sys.exit("mktop_go.py: %s: %d matches of %r" % (what, s.count(old), old[:70]))
    return s.replace(old, new)


def cut(s, start, end, new, what):
    if s.count(start) != 1:
        sys.exit("mktop_go.py: %s: %d matches of %r" % (what, s.count(start), start[:70]))
    i = s.index(start)
    j = s.index(end, i) + len(end)
    return s[:i] + new + s[j:]


g = open(os.path.join(SRC, "rtl/karabas_minig_top.v")).read()
v1 = subprocess.check_output(["git", "show", "%s:src/rtl/karabas_go_top.v" % V1_REF], cwd=SRC).decode()

# the header and ports of the v1 Go top
i = v1.index("module karabas_go_top")
head = v1[:v1.index(");", i) + 2] + "\n"
head = head.replace("inout wire [1:0] MCU_SPI_IO,", "inout wire [1:0] MCU_SPI_IO,  // [0] INT of link v2 (N9), [1] unused (M11)")
i = g.index("module karabas_minig_top")
body = g[g.index("\n);\n", i) + 4:]

b = body
b = sub(b, "// ft clk 8mhz out\n"
           "ODDR2 u_ft_clk (.Q(FT_CLK_OUT), .C0(clk_8mhz), .C1(~clk_8mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n",
        "// the midi clock of the SAM2695 (12 MHz); the Go has no FT_CLK_OUT (the FT812 has its own crystal)\n"
        "ODDR2 u_midi_clk (.Q(MIDI_CLK), .C0(clk_12mhz), .C1(~clk_12mhz), .CE(1'b1), .D0(1'b1), .D1(1'b0), .R(1'b0), .S(1'b0));\n",
        "ft clk")
b = sub(b, "// clk_sys enable of the edges of clk_bus, for the SRAM controller\nwire ce_28m;\n"
           "bus_ce bus_ce(.clk_sys(clk_sys), .clk_bus(clk_bus), .ce(ce_28m), .v_clk());\n",
        "// clk_sys enables of the edges of clk_bus: ce_28m for the SRAM controller, v_clk for the V_CLK pin\nwire ce_28m, v_clk;\n"
        "bus_ce bus_ce(.clk_sys(clk_sys), .clk_bus(clk_bus), .ce(ce_28m), .v_clk(v_clk));\n", "bus_ce")
# the ADC / ESP inputs of tsconf are under `ifdef HW_ID2 / HW_ID3: not built on the Go (HW_ID1)
b = sub(b, "	.vga_60hz			(kb_vga_60hz),\n",
        "	.vga_60hz			(kb_vga_60hz),\n\n"
        "	// the floppy connector of the Go (the physical drive of the FDC of tsconf)\n"
        "	.fdc_side			(FDC_SIDE_N),\n	.fdc_rdata			(FDC_RDATA),\n	.fdc_wprt			(FDC_WPRT),\n"
        "	.fdc_tr00			(FDC_TR00),\n	.fdc_index			(FDC_INDEX),\n	.fdc_wg				(FDC_WGATE),\n"
        "	.fdc_wr_data		(FDC_WDATA),\n	.fdc_step			(FDC_STEP),\n	.fdc_dir				(FDC_DIR),\n"
        "	.fdc_motor			(FDC_MOTOR),\n	.fdc_ds				(FDC_DRIVE),\n", "fdc")
b = sub(b, "	.midi_reset_n		(),\n", "	.midi_reset_n		(MIDI_RESET_N),\n", "midi reset")
b = sub(b, "// MCU_SCK on a global buffer: XST left it on the IBUF, and the 74 flip-flops of the SPI receiver on local routing\n"
           "// had several ns of clock skew (hold not met). The SCK passed to the FT812 (FT_SPI_SCK) is taken before the BUFG,\n"
           "// a BUFG drives clock pins only.\n"
           "wire mcu_sck_ibufg, mcu_sck;\nIBUFG ibufg_mcu_sck(.I(MCU_SCK), .O(mcu_sck_ibufg));\nBUFG bufg_mcu_sck(.I(mcu_sck_ibufg), .O(mcu_sck));\n",
        "// MCU_SCK is not on a clock pin on the Go (CLOCK_DEDICATED_ROUTE = FALSE in the ucf)\n"
        "wire mcu_sck = MCU_SCK, mcu_sck_ibufg = MCU_SCK;\n", "mcu sck")
b = sub(b, "assign espcs_in = (~ESP32_SPI_CS_N) ? 0 : 1;\nassign ESP32_SPI_CS_N = esp_ft_spi_dis ? (espcs_n ? 1'bZ : 1'b0) : espcs_n;\n",
        "assign espcs_in = 1'b1;\nassign ESP_RESET_N = 1'bZ;\nassign ESP_BOOT_N = 1'bZ;\nassign BEEPER = audio_beeper;\n", "esp")
b = sub(b, "assign ftint = FT_INT_N;\n",
        "assign ftint = FT_INT_N;\nassign FT_OE_N = esp_ft_spi_dis ? 1'b0 : (mcu_ft_vga_on ? 1'b0 : ~vdac2_sel);\n", "ft oe")
b = cut(b, "// FT_CLK: the pixel clock of the FT812 (its video is taken on its falling edge, hdmi_pll measures it). It was a",
        "assign audio_mix_r = audio_out_r;\n", """// the FT812 and the FPGA share the video DAC: the FT812 drives it when the core (vdac2_sel) or the
// firmware (FT_VGA_ON) asks for it
wire ft_video_active = vdac2_sel | mcu_ft_vga_on;
assign VGA_R[7:0] = ft_video_active ? 8'bZZZZZZZZ : osd_r[7:0];
assign VGA_G[7:0] = ft_video_active ? 8'bZZZZZZZZ : osd_g[7:0];
assign VGA_B[7:0] = ft_video_active ? 8'bZZZZZZZZ : osd_b[7:0];
assign VGA_HS = ft_video_active ? 1'bZ : osd_hs;   // the syncs of the overlay: in step with osd_rgb
assign VGA_VS = ft_video_active ? 1'bZ : osd_vs;
assign V_CLK = ft_video_active ? FT_CLK : v_clk;

// ------- i2s DAC --------------
kg_pcm5102 #(.DIV_BITS(1)) PCM5102(
	.clk				(clk_bus),
	.reset			(areset),
	.left				(audio_mix_l),
	.right			(audio_mix_r),
	.din				(DAC_DAT),
	.bck				(DAC_BCK),
	.lrck				(DAC_LRCK)
);
assign DAC_MUTE = 1'b1; // soft mute, 0 = mute, 1 = unmute

// ------- audio mix
assign audio_mix_l = audio_out_l;
assign audio_mix_r = audio_out_r;
""", "video and audio")
b = sub(b, "assign MCU_IO[1] = mcu_int;\nassign MCU_IO[0] = 1'bz;\nassign MCU_IO[5:2] = 4'bzzzz;\n",
        "assign MCU_SPI_IO[0] = mcu_int;   // INT of link v2 on N9 (IO1 of the firmware)\nassign MCU_SPI_IO[1] = 1'bz;\n", "mcu io")
b = sub(b, "	.MCU_SPI_FT_SS	(MCU_IO[3]),", "	.MCU_SPI_FT_SS	(MCU_SPI_FT_CS_N),", "ft ss")

i = b.index("dot_matrix dot_matrix(")
b = b[:i] + "// no dot matrix on the Go: MATRIX_CMD of kg_mcu2 stays 0\nassign matrix_cmd = 24'd0;\nassign matrix_cmd_wr = 1'b0;\n\n" + b[b.index(");", i) + 3:]

out = head + "// karabas: made by src/tools/mktop_go.py from karabas_minig_top.v (do not edit it, change Mini G)\n" + b
open(os.path.join(SRC, "rtl/karabas_go_top.v"), "w").write(out)
print("mktop_go.py: rtl/karabas_go_top.v")
