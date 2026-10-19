#!/bin/bash
# tb_hdmi_top (ISim): hdmi_top with zhdmi (karabas-go-modules), the core video at 28 MHz and the FT812
# at 40 / 72 MHz through hdmi_pll, the pixels and the audio samples where they enter hdmi_tx.
# zhdmi runs as a Verilog netlist of ghdl --synth: ISim 14.7 stops with an internal error in
# zhdmi_island_encoder.vhd, and ghdl needs two runs, dvi.vhd is VHDL-2008 and zhdmi_packet_gen.vhd
# VHDL-93 (karabas-go-modules sim/lint/ghdl_check.py); for this the copy of zhdmi_tx.vhd takes dvi
# as a component. ODDR2 / OBUFDS and the clock primitives are the unisim models of ISE.
# Usage: src/sim/run_hdmi_sim.sh [path to ISE_DS/settings64.sh]
# Prints "tb_hdmi_top: 0 errors"; the script fails on any other count.

set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
SAMPLERATE=48000
SIM="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$SIM")"
MOD="$SRC/../modules"
H="$MOD/rtl/video/hdmi"
OUT="$SIM/build/hdmi"
mkdir -p "$OUT/w93" "$OUT/w08"
cd "$OUT"

# ---- zhdmi as Verilog ----
python3 - "$H/zhdmi_tx.vhd" zhdmi_tx_sim.vhd <<'PY'
import re, sys
s = open(sys.argv[1]).read()
comp = ("\tcomponent dvi port (CLK, RESET : in std_logic; RGB : in std_logic_vector(23 downto 0);\n"
	"\t\tHSYNC, VSYNC, DE : in std_logic; ENC_RED, ENC_GREEN, ENC_BLUE : out std_logic_vector(9 downto 0));\n"
	"\tend component;\n")
s, n1 = re.subn(r"(architecture rtl of hdmi_tx is\n)", lambda m: m.group(1) + comp, s)
s, n2 = re.subn(r"\bdvi: entity work\.dvi port map\(", "dvi_inst: dvi port map(", s)
assert n1 == 1 and n2 == 1, "zhdmi_tx.vhd changed: update run_hdmi_sim.sh"
open(sys.argv[2], "w").write(s)
PY
ghdl -a --std=93c --workdir=w93 --work=unisim "$MOD/sim/lint/unisim_stubs.vhd"
ghdl --synth --std=93c --ieee=synopsys --workdir=w93 -Pw93 --out=verilog -gSAMPLE_FREQ=$SAMPLERATE \
	"$H/zhdmi_tmds_encoder.vhd" "$H/zhdmi_tmds_serializer_spartan6.vhd" "$H/zhdmi_audio_packetizer.vhd" \
	"$H/zhdmi_island_encoder.vhd" "$H/zhdmi_packet_gen.vhd" "$H/zhdmi_signaling.vhd" zhdmi_tx_sim.vhd \
	-e hdmi_tx > hdmi_tx_vhdl.v 2> ghdl93.log || { cat ghdl93.log; exit 1; }
# hdmi_top sets SAMPLE_FREQ, built in above
sed -i '/^module hdmi_tx$/,/);/{/);/a\  parameter SAMPLE_FREQ = 0;
}' hdmi_tx_vhdl.v
grep -q "parameter SAMPLE_FREQ = 0;" hdmi_tx_vhdl.v || { echo "no hdmi_tx module in the netlist"; exit 1; }
ghdl --synth --std=08 --ieee=synopsys --workdir=w08 --out=verilog "$H/dvi_encoder.vhd" "$H/dvi.vhd" -e dvi \
	> dvi_vhdl.v 2> ghdl08.log || { cat ghdl08.log; exit 1; }

# ---- ISim ----
set --
source "$SETTINGS" > /dev/null
cat > tb_hdmi_top.prj <<PRJ
vhdl work "$SRC/rtl/hdmi/freq_counter.vhd"
verilog work "hdmi_tx_vhdl.v"
verilog work "dvi_vhdl.v"
verilog work "$H/pll_reset.v"
verilog work "$SRC/rtl/hdmi/hdmi_pll.v"
verilog work "$SRC/rtl/hdmi/hdmi_top.v"
verilog work "$SIM/tb_hdmi_top.v"
verilog work "$XILINX/verilog/src/glbl.v"
PRJ
fuse -prj tb_hdmi_top.prj -L unisims_ver -top work.tb_hdmi_top -top work.glbl -generic_top "SAMPLERATE=$SAMPLERATE" \
	-o tb_hdmi_top.exe > fuse.log || { grep -E "ERROR" fuse.log | head; exit 1; }
echo "run all; quit" > run.tcl
./tb_hdmi_top.exe -tclbatch run.tcl > tb_hdmi_top.log 2>&1 || true
grep -E "tb_hdmi_top|ERROR|MHz" tb_hdmi_top.log | head -30
grep -q "tb_hdmi_top: 0 errors" tb_hdmi_top.log || { echo "tb_hdmi_top FAILED"; exit 1; }
echo "HDMI SIMULATION PASSED"
