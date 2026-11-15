#!/bin/bash
# The OPL4: tb_opl4 (iverilog, about a minute), opl4_kg with a Z80 (tv80) running opl4_z80.asm (sjasmplus)
# and its sample memory through port 2 of gs_top, sdram2p and sdram_model; the ROM from the FL loader.
# The FM part is a stub here (opl3_fpga as it is, checked in u16_tsconf_gs_v24).
# Then tb_opl4_lpf: audio_lpf with a 5 / 15 kHz tone at 44.1 kHz (the OPL4) and at 37.47 kHz (the GS),
# taken at the PCM5102 rate (54.7 kHz); opl4_lpf.py prints the tone and the worst other component, the
# script wants the low-pass mode (2) at least the given dB below the tone.
# Usage: src/sim/run_opl4_sim.sh
# Prints "tb_opl4: 0 errors"; the script fails on any other count.
set -e
SIM="$(cd "$(dirname "$0")" && pwd)"
R="$(dirname "$SIM")/rtl"
SJASM=${SJASM:-$(command -v sjasmplus || echo /opt/sjasmplus/sjasmplus)}
OUT="$SIM/build/opl4"
mkdir -p "$OUT"
cd "$OUT"
"$SJASM" --nologo "$SIM/opl4/opl4_z80.asm" > sjasm.log || { cat sjasm.log; exit 1; }
xxd -p -c 1 opl4_z80.bin > opl4_z80.hex
iverilog -g2012 -o tb_opl4 "$SIM/opl4/tb_opl4.v" "$SIM/opl4/t80s_stub.v" "$SIM/opl4/opl3_fm_stub.v" "$SIM"/opl4/tv80/*.v \
	"$SIM/sdram_model.v" "$SIM/lib/ODDR2.v" "$R/ram/sdram2p.v" "$R/z80-silicon/z80_silicon_cen.v" "$R/z80-silicon/z80s_t80pa.v" \
	"$R/sound/gs.v" "$R/sound/gs_top.v" \
	"$R/sound/opl4/opl4_kg.v" "$R/sound/opl4/opl4.v" "$R/sound/opl4/opl4_powtab.v" "$R/sound/opl4/opl4_inctab.v"
vvp -n tb_opl4 | tee tb_opl4.log | grep "tb_opl4: "
grep -q "tb_opl4: 0 errors" tb_opl4.log || { echo "tb_opl4 FAILED"; exit 1; }
for P in "0 5000 50" "0 15000 30" "1 5000 38" "1 15000 12"; do
	set -- $P
	for M in 0 1 2; do
		iverilog -g2012 -P tb_opl4_lpf.GS=$1 -P tb_opl4_lpf.FREQ=$2 -P tb_opl4_lpf.MODE=$M -o tb_opl4_lpf \
			"$SIM/opl4/tb_opl4_lpf.v" "$R/sound/audio_lpf.v"
		vvp -n tb_opl4_lpf > /dev/null
		L=$(python3 "$SIM/opl4/opl4_lpf.py" opl4_lpf.txt $2)
		echo "tb_opl4_lpf $([ $1 = 1 ] && echo GS || echo OPL4) mode $M: $L"
	done
	python3 -c "import sys; sys.exit(0 if float('$L'.split('(')[1].split(' dB')[0]) >= $3 else 1)" || \
		{ echo "tb_opl4_lpf FAILED: mode 2 at $2 Hz under $3 dB"; exit 1; }
done
echo "OPL4 SIMULATION PASSED"
