#!/bin/bash
# The OPL4 FM part (opl3_fm, the generated opl3_fm_gen.v) against ymfm ymf262 (github.com/aaronsgiles/ymfm,
# cloned into build/ymfm_src when missing): tb_fm.cpp (Verilator) plays the OPL instruments of MoonBlaster
# songs (patches.py) on channel 0; noise.py the noise outside the harmonics of each note (ref, rtl, and the
# resampling to 44.1 kHz modelled); then tb_kg.cpp, opl4_kg itself (FM -> OUT_L), kgnoise.py with and
# without its FM interpolation.
# Usage: src/sim/opl3ref/run.sh disk.trd...
set -e
D="$(cd "$(dirname "$0")" && pwd)"
SIM="$(dirname "$D")"
R="$(dirname "$SIM")/rtl/sound/opl4"
B="$SIM/build/opl3ref"
mkdir -p "$B" "$SIM/build/ymfm_src"
[ -d "$SIM/build/ymfm_src/ymfm" ] || git clone -q --depth 1 https://github.com/aaronsgiles/ymfm.git "$SIM/build/ymfm_src/ymfm"
Y="$SIM/build/ymfm_src/ymfm/src"
python3 -I "$D/patches.py" "$@" > "$B/patches.txt"
cd "$B"
verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-lint -Wno-style --x-initial 0 \
	-CFLAGS "-O2 -I$Y -std=c++17" "$R/opl3_fm_gen.v" "$D/tb_fm.cpp" \
	"$Y/ymfm_opl.cpp" "$Y/ymfm_pcm.cpp" "$Y/ymfm_misc.cpp" "$Y/ymfm_adpcm.cpp" "$Y/ymfm_ssg.cpp" \
	--top-module opl3_fm -o tb_fm > verilator.log 2>&1 || { grep -m10 -i error verilator.log; exit 1; }
mkdir -p dump
./obj_dir/tb_fm patches.txt > tb_fm.log; tail -1 tb_fm.log
python3 -I "$D/noise.py" dump | tail -1
# opl4_kg (the FM path into the 44.1 kHz output): 20 patches without and with the FM interpolation
verilator --cc --exe --build -j 4 -O2 -Wno-fatal -Wno-lint -Wno-style --x-initial 0 --Mdir obj_kg -CFLAGS "-O2" \
	"$R/opl4_kg.v" "$R/opl4.v" "$R/opl4_powtab.v" "$R/opl4_inctab.v" "$R/opl3_fm_gen.v" "$D/tb_kg.cpp" \
	--top-module opl4_kg -o tb_kg > verilator_kg.log 2>&1 || { grep -m10 -i error verilator_kg.log; exit 1; }
./obj_kg/tb_kg patches.txt 0 0 20 > /dev/null
./obj_kg/tb_kg patches.txt 1 0 20 > /dev/null
python3 -I "$D/kgnoise.py" dump
