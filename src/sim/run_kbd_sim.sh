#!/bin/bash
# tb_kbd_rtc (ISim): the PS/2 keyboard buffer read through the RTC registers F0..FF and the key matrix,
# kg_mcu and hid_parser as wired in the tops.
# Usage: src/sim/run_kbd_sim.sh [path to ISE_DS/settings64.sh]
# Prints "tb_kbd_rtc: 0 errors"; the script fails on any other count.

set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
SIM="$(cd "$(dirname "$0")" && pwd)"
SRC="$(dirname "$SIM")"
M="$SRC/../modules/rtl"
OUT="$SIM/build/kbd"
mkdir -p "$OUT"
cd "$OUT"
set --
source "$SETTINGS" > /dev/null
vlogcomp -work work -i $M/mcu $M/mem/kg_fifo.v $M/mem/kg_sdpram.v $M/mcu/kg_spi_slave.v $M/mcu/kg_burst_rx.v \
	$M/mcu/kg_mcu_link.v $M/mcu/kg_mcu_ctl.v $M/mcu/kg_mcu_hid.v $M/mcu/kg_mcu_loader.v $M/mcu/kg_mcu_rtc.v \
	$M/mcu/kg_mcu_uart.v $M/mcu/kg_mcu_img.v $M/mcu/kg_mcu_debug.v $M/mcu/kg_mcu.v \
	"$SRC/rtl/mcu/usb_ps2_keybuf.v" > vlogcomp.log || { grep ERROR vlogcomp.log; exit 1; }
vhpcomp -work work "$SRC/rtl/mcu/hid_parser.vhd" "$SIM/tb_kbd_rtc.vhd" > vhpcomp.log || { grep ERROR vhpcomp.log; exit 1; }
fuse -top work.tb_kbd_rtc -o tb_kbd_rtc.exe > fuse.log || { grep ERROR fuse.log; exit 1; }
echo "run 1 ms; quit" > run.tcl
./tb_kbd_rtc.exe -tclbatch run.tcl > tb_kbd_rtc.log 2>&1 || true
grep -E "ERROR|tb_kbd_rtc" tb_kbd_rtc.log | head -20
grep -q "tb_kbd_rtc: 0 errors" tb_kbd_rtc.log || { echo "tb_kbd_rtc FAILED"; exit 1; }
echo "KBD SIMULATION PASSED"
