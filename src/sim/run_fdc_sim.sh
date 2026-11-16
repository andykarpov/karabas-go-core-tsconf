#!/bin/bash
# The FDC of the Go: tb_hrdy_fdc (iverilog), hrdy_fdc with a model of a drive, at 28 MHz and at 24 MHz (DS80),
# with the disk at the nominal speed and 2 % off, the CPU in turbo x8 and at 3.5 MHz; then tb_fdc_z80s, the same
# drive (fdc_drive.vh) with z80-silicon running fdc_z80s.asm (Restore, Read / Write Sector by INI / OUTI, the poll).
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
	iverilog -g2012 -I "$V" -I "$SIM" -P tb_hrdy_fdc.DS80=$1 -P tb_hrdy_fdc.SPEED=$2 -P tb_hrdy_fdc.TURBO=$3 -o tb_hrdy_fdc \
		"$SIM/tb_hrdy_fdc.v" "$V"/vg93_*.v "$V/fdd_glue.v" "$V/hrdy_fdc.v"
	vvp -n tb_hrdy_fdc | tee tb_hrdy_fdc_$1_$2_$3.log | grep "tb_hrdy_fdc: "
	grep -q ": 0 errors" tb_hrdy_fdc_$1_$2_$3.log || FAIL=1
done
[ $FAIL = 0 ] || { echo "tb_hrdy_fdc FAILED"; exit 1; }
# tb_fdc_z80s: the CPU of tsconf.v (z80-silicon) running fdc_z80s.asm against hrdy_fdc, 14 / 7 / 3.5 MHz (a minute)
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}
Z="$(dirname "$SIM")/rtl/z80-silicon"
"$SJASM" --nologo --raw=fdc_z80s.bin "$SIM/fdc_z80s.asm" > sjasm.log || { cat sjasm.log; exit 1; }
xxd -p -c 1 fdc_z80s.bin > fdc_z80s.hex
for P in 0 1 2; do
	iverilog -g2012 -I "$V" -I "$SIM" -P tb_fdc_z80s.PATTERN=$P -o tb_fdc_z80s_$P "$SIM/tb_fdc_z80s.v" "$Z/z80_silicon_cen.v" \
		"$Z/z80s_t80pa.v" "$V"/vg93_*.v "$V/fdd_glue.v" "$V/hrdy_fdc.v"
	(vvp -n tb_fdc_z80s_$P > tb_fdc_z80s_$P.log) &
done
wait
for P in 0 1 2; do
	grep "tb_fdc_z80s: " tb_fdc_z80s_$P.log | grep -v "^tb_fdc_z80s: [rw]"
	grep -q ", 0 errors" tb_fdc_z80s_$P.log || FAIL=1
done
[ $FAIL = 0 ] || { echo "tb_fdc_z80s FAILED"; exit 1; }
echo "FDC SIMULATION PASSED"
