#!/bin/bash
# The OPL4 wave part (opl4.v) against ymfm (github.com/aaronsgiles/ymfm, BSD, cloned into build/ymfm_src
# when missing): tb_ref.cpp (Verilator), scripts of gen.py per part, without and with the interpolation
# (interp of opl4.v against ymfm with the interpolation of openMSX, pcm_interp.py). Needs the YRW801 ROM (2 MB).
# Usage: src/sim/opl4ref/run.sh /path/yrw801.rom [modes...]   (modes: plain env lfo rev tl multi rand)
set -e
ROM=$(realpath "$1"); shift
MODES=${*:-plain env lfo rev tl multi rand}
D="$(cd "$(dirname "$0")" && pwd)"
SIM="$(dirname "$D")"
R="$(dirname "$SIM")/rtl/sound/opl4"
B="$SIM/build/opl4ref"
mkdir -p "$B" "$SIM/build/ymfm_src"
[ -d "$SIM/build/ymfm_src/ymfm" ] || git clone -q --depth 1 https://github.com/aaronsgiles/ymfm.git "$SIM/build/ymfm_src/ymfm"
Y="$SIM/build/ymfm_src/ymfm/src"
cd "$B"
# the reference with the interpolation of openMSX (OPL4_INTERP=1): patched copies of ymfm_pcm.{h,cpp} here
mkdir -p yp
sed 's/\tint16_t fetch_sample() const;/\tint16_t fetch_sample() const;\n\tint16_t fetch_sample_at(uint32_t pos) const;/' "$Y/ymfm_pcm.h" > yp/ymfm_pcm.h
grep -q fetch_sample_at yp/ymfm_pcm.h
python3 -I "$D/pcm_interp.py" "$Y/ymfm_pcm.cpp" yp/ymfm_pcm.cpp
verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-lint -Wno-style --x-initial 0 \
	-CFLAGS "-O2 -I$B/yp -I$Y -std=c++17" "$R/opl4.v" "$R/opl4_powtab.v" "$R/opl4_inctab.v" "$D/tb_ref.cpp" \
	"$Y/ymfm_opl.cpp" "$B/yp/ymfm_pcm.cpp" "$Y/ymfm_misc.cpp" "$Y/ymfm_adpcm.cpp" "$Y/ymfm_ssg.cpp" \
	-GDEADLINE=999999 --top-module opl4 -o tb_ref > verilator.log 2>&1 || { grep -m10 -i error verilator.log; exit 1; }
FAIL=0
for I in 0 1; do
	for m in $MODES; do
		for s in 1 2; do
			python3 -I "$D/gen.py" $m $s > $m$s.txt
			OPL4_INTERP=$I ./obj_dir/tb_ref "$ROM" $m$s.txt $s 4 40 > i$I-$m$s.log || FAIL=1
			echo "interp $I $m $s: $(tail -1 i$I-$m$s.log)"
		done
	done
done
[ $FAIL = 0 ] && echo "OPL4 REF PASSED" || { echo "OPL4 REF: mismatches (see $B/*.log)"; exit 1; }
