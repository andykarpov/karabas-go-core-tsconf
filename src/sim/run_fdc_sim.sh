#!/bin/bash
# The FDC of the Go: tb_hrdy_fdc (iverilog), hrdy_fdc with a model of a drive, at 28 MHz and at 24 MHz (DS80),
# with the disk at the nominal speed and 2 % off, the CPU in turbo x8 and at 3.5 MHz.
# Usage: src/sim/run_fdc_sim.sh
set -e
SIM="$(cd "$(dirname "$0")" && pwd)"
V="$(dirname "$SIM")/rtl/vg93"
OUT="$SIM/build/fdc"
mkdir -p "$OUT"
cp "$V/vg93-microcode-rom.hex" "$OUT/"
cd "$OUT"
FAIL=0
for P in "0 1.0 1" "1 1.0 1" "0 1.02 1" "1 0.98 1" "0 1.0 0" "1 1.0 0"; do
	set -- $P
	iverilog -g2012 -I "$V" -P tb_hrdy_fdc.DS80=$1 -P tb_hrdy_fdc.SPEED=$2 -P tb_hrdy_fdc.TURBO=$3 -o tb_hrdy_fdc \
		"$SIM/tb_hrdy_fdc.v" "$V"/vg93_*.v "$V/fdd_glue.v" "$V/hrdy_fdc.v"
	vvp -n tb_hrdy_fdc | tee tb_hrdy_fdc_$1_$2_$3.log | grep "tb_hrdy_fdc: "
	grep -q ": 0 errors" tb_hrdy_fdc_$1_$2_$3.log || FAIL=1
done
[ $FAIL = 0 ] || { echo "tb_hrdy_fdc FAILED"; exit 1; }
echo "FDC SIMULATION PASSED"
