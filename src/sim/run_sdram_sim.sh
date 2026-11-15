#!/bin/bash
# The SDRAM of the sound: tb_sdram2p (iverilog), sdram2p with both ports busy, and tb_gs_top (ISim), the GS
# with its read cache running a test ROM (gs_memtest.asm, sjasmplus) while the OPL4 and the FL loader
# use port 2. Both with sdram_model (CL 3, timing checks).
# Usage: src/sim/run_sdram_sim.sh [path to ISE_DS/settings64.sh]
# Prints "tb_sdram2p: 0 errors" and "tb_gs_top: 0 errors"; the script fails on any other count.

set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
SIM="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$SIM")"
R="$SRC/rtl"
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}

OUT="$SIM/build/sdram"
mkdir -p "$OUT"
cd "$OUT"
iverilog -g2012 -o tb_sdram2p "$SIM/tb_sdram2p.v" "$SIM/sdram_model.v" "$SIM/lib/ODDR2.v" "$R/ram/sdram2p.v"
vvp -n tb_sdram2p | tee tb_sdram2p.log | grep "tb_sdram2p: "
grep -q "tb_sdram2p: 0 errors" tb_sdram2p.log || { echo "tb_sdram2p FAILED"; exit 1; }

OUT="$SIM/build/gs"
mkdir -p "$OUT"
cd "$OUT"
"$SJASM" --nologo --raw=gs_memtest.bin "$SIM/gs_memtest.asm" > sjasm.log || { cat sjasm.log; exit 1; }
xxd -p -c 1 gs_memtest.bin > gs_memtest.hex
set --
source "$SETTINGS" > /dev/null
vhpcomp -work work "$R/T80/T80_Pack.vhd" "$R/T80/T80_ALU.vhd" "$R/T80/T80_Reg.vhd" "$R/T80/T80_MCode.vhd" \
	"$R/T80/T80.vhd" "$R/T80/T80s.vhd" > vhpcomp.log || { grep ERROR vhpcomp.log; exit 1; }
vlogcomp -work work "$SIM/lib/ODDR2.v" "$SIM/sdram_model.v" "$R/ram/sdram2p.v" "$R/z80-silicon/z80_silicon_cen.v" \
	"$R/z80-silicon/z80s_t80pa.v" "$R/sound/gs.v" \
	"$R/sound/gs_top.v" "$SIM/tb_gs_top.v" > vlogcomp.log || { grep ERROR vlogcomp.log; exit 1; }
fuse -top work.tb_gs_top -o tb_gs_top.exe > fuse.log || { grep ERROR fuse.log; exit 1; }
echo "run 10 ms; quit" > run.tcl
./tb_gs_top.exe -tclbatch run.tcl > tb_gs_top.log 2>&1 || true
grep -E "ERROR|tb_gs_top" tb_gs_top.log | head -20
grep -q "tb_gs_top: 0 errors" tb_gs_top.log || { echo "tb_gs_top FAILED"; exit 1; }
echo "SDRAM SIMULATION PASSED"
