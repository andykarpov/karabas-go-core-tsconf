#!/bin/bash
# The rewrites of the timing work against the old code (sim/ref, the versions of cec5631):
#   tb_eq_zports (iverilog):  zports, the registers on zclk now on clk_bus with zpos, the IDE trigger latches
#   tb_eq_saa (iverilog):     saa1099 on clk_bus with the 8 MHz enable against the one on its own clock
#   tb_bus_ce (ISim):         bus_ce (ce_28m, v_clk) with the PLL of the tops
# Usage: src/sim/run_eq_sim.sh [path to ISE_DS/settings64.sh]
# Each test prints "<tb>: 0 errors"; the script fails on any other count.

set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
SIM="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$SIM")"
RTL="$SRC/rtl"
OUT="$SIM/build/eq"
mkdir -p "$OUT/bus_ce"

result() {
	grep -E "$1: " "$2" | head -8
	grep -q "$1: 0 errors" "$2" || { echo "$1 FAILED"; exit 1; }
}

# ---- iverilog ----
iverilog -g2001 -I "$RTL/tsconf" -o "$OUT/tb_eq_zports" "$SIM/tb_eq_zports.v" "$SIM/ref/zports_ref.v" \
	"$RTL/tsconf/zports.v" "$RTL/tsconf/zclock.v"
vvp -n "$OUT/tb_eq_zports" > "$OUT/tb_eq_zports.log"
result tb_eq_zports "$OUT/tb_eq_zports.log"

iverilog -g2001 -o "$OUT/tb_eq_saa" "$SIM/tb_eq_saa.v" "$SIM/ref/saa1099_ref.v" "$RTL/sound/saa1099.v"
# both read saa1099_compressor_lut.hex from the current directory
(cd "$RTL/sound" && vvp -n "$OUT/tb_eq_saa") > "$OUT/tb_eq_saa.log"
result tb_eq_saa "$OUT/tb_eq_saa.log"

# ---- ISim ----
set --
source "$SETTINGS" > /dev/null
cd "$OUT/bus_ce"
cat > tb_bus_ce.prj <<PRJ
verilog work "$SRC/../modules/rtl/clk/kg_pll.v"
verilog work "$RTL/bus_ce.v"
verilog work "$SIM/tb_bus_ce.v"
verilog work "$XILINX/verilog/src/glbl.v"
PRJ
fuse -prj tb_bus_ce.prj -L unisims_ver -top work.tb_bus_ce -top work.glbl -o tb_bus_ce.exe > fuse.log \
	|| { grep ERROR fuse.log; exit 1; }
echo "run all; quit" > run.tcl
./tb_bus_ce.exe -tclbatch run.tcl > tb_bus_ce.log 2>&1 || true
result tb_bus_ce "$OUT/bus_ce/tb_bus_ce.log"
echo "EQ SIMULATION PASSED"
