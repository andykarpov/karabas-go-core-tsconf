#!/bin/bash
# z80-silicon (Verilator, about half a minute):
# 1. tb_z80s_cen: z80_silicon_cen.v of gen_cen.py (one clock, cen_p / cen_n) against z80-silicon as it is on
#    the two edges of its clock, every output at every clock, for the four patterns of the enables (14 / 7 /
#    3.5 MHz of zclock, random gaps), random opcodes, INT, NMI, WAIT, BUSRQ.
# 2. tb_z80s_t80: z80-silicon against T80pa of tsconf.v (a ghdl --synth netlist) on the enables of tsconf:
#    the bus at every clock and the registers after each group of instructions, with the known differences
#    of T80pa out of the stream (SKIP = 15, see the testbench): the four patterns with WAIT, INT and NMI
#    (CLEAN: away from the clock where T80pa samples them later than the chip).
# Verilator, not iverilog: the core has registers without an initial value, which stay X in a 4-state
# simulator; --x-initial 0 is their value in the FPGA.
# Usage: src/sim/run_z80s_sim.sh   (regenerates z80_silicon_cen.v first)
# The script fails on any difference.
set -e
SIM="$(cd "$(dirname "$0")" && pwd)"
RTL="$(dirname "$SIM")/rtl"
Z="$RTL/z80-silicon"
OUT="$SIM/build/z80s"
mkdir -p "$OUT/t80/src"
python3 -I "$Z/gen_cen.py"
cd "$OUT"

# T80pa as Verilog: ghdl --synth (VHDL-2008, the std_logic_unsigned of T80.vhd needs -fsynopsys). Two fixes
# of its names: the instance labels renamed (VHDL is not case sensitive: the signal ALU_Q of T80 and the
# port Q of the instance alu both become alu_q), and the escaped "\reg " after a prefix made plain.
T="$RTL/T80"
cp "$T/T80_Pack.vhd" "$T/T80_Reg.vhd" "$T/T80_MCode.vhd" "$T/T80_ALU.vhd" t80/src/
sed 's/^\tmcode : T80_MCode/\tu_mcode : T80_MCode/; s/^\talu : T80_ALU/\tu_alu : T80_ALU/; s/^\tRegs : T80_Reg/\tu_regs : T80_Reg/' \
	"$T/T80.vhd" > t80/src/T80.vhd
sed 's/^    u0 : T80/    u_t80 : T80/' "$T/T80pa.vhd" > t80/src/T80pa.vhd
(cd t80 && rm -f ./*.cf && ghdl --synth --std=08 -fsynopsys --workdir=. --out=verilog src/T80_Pack.vhd src/T80_Reg.vhd \
	src/T80_MCode.vhd src/T80_ALU.vhd src/T80.vhd src/T80pa.vhd -e t80pa > t80pa_vhdl.v 2> ghdl.log) || { cat t80/ghdl.log; exit 1; }
sed -i 's/u_t80_\\reg /u_t80_reg_x/g' t80/t80pa_vhdl.v

VL="verilator --binary --timing --default-language 1364-2005 -Wno-fatal -Wno-lint -Wno-style --x-initial 0 --x-assign 0 -O2"
build() {   # build <dir> <top> <files...> -- <params>
	local D=$1 TOP=$2; shift 2
	local F=() ; while [ "$1" != "--" ]; do F+=("$1"); shift; done; shift
	$VL "$@" --top-module $TOP -Mdir $D "${F[@]}" -o tb > $D.log 2>&1 || { grep -m5 "%Error" $D.log; echo "no build: $D"; return 1; }
}
CEN=("$SIM/z80s/tb_z80s_cen.v" "$Z/z80_silicon_cen.v" "$Z/Z80.v" "$Z/Registers.v" "$Z/Register_selector.v")
T80=("$SIM/z80s/tb_z80s_t80.v" "$Z/z80_silicon_cen.v" t80/t80pa_vhdl.v)
RUNS=()
for P in 0 1 2 3; do
	build cen$P tb_z80s_cen "${CEN[@]}" -- -GPATTERN=$P & RUNS+=(cen$P)
	build t80w$P tb_z80s_t80 "${T80[@]}" -- -GPATTERN=$P -GINPUTS=4 -GSKIP=15 -GMAXSHOW=0 & RUNS+=(t80w$P)
done
build t80int tb_z80s_t80 "${T80[@]}" -- -GPATTERN=1 -GINPUTS=1 -GCLEAN=1 -GSTOP_REG=0 -GSKIP=15 -GMAXSHOW=0 & RUNS+=(t80int)
build t80nmi tb_z80s_t80 "${T80[@]}" -- -GPATTERN=3 -GINPUTS=2 -GCLEAN=1 -GSTOP_REG=0 -GSKIP=15 -GMAXSHOW=0 & RUNS+=(t80nmi)
wait
FAIL=0
for R in "${RUNS[@]}"; do
	[ -x $R/tb ] || { echo "$R: no build"; FAIL=1; continue; }
	./$R/tb > $R.out
	case $R in
	cen*)
		grep "tb_z80s_cen: " $R.out | sed "s/^/$R: /" | grep "pattern\|errors"
		grep -q "tb_z80s_cen: 0 errors" $R.out || FAIL=1 ;;
	t80*)
		grep "tb_z80s_t80: " $R.out | grep "pattern\|M1 compared\|differs after" | sed "s/^/$R: /"
		if grep -q "DIVERGED\|differs in" $R.out; then grep "DIVERGED\|differs in" $R.out | sed "s/^/$R: /"; FAIL=1; fi
		case $R in t80w*) grep -q " 0 with a register difference" $R.out || FAIL=1 ;; esac ;;
	esac
done
[ $FAIL = 0 ] || { echo "Z80S SIMULATION FAILED"; exit 1; }
echo "Z80S SIMULATION PASSED"
