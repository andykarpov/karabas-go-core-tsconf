#!/bin/bash
# Simulate tb_mcu_burst.vhd with ISim (Xilinx ISE 14.7).
# Usage: src/sim/run_burst_sim.sh [path to ISE_DS/settings64.sh]

set -e
SETTINGS=${1:-/opt/Xilinx/14.7/ISE_DS/settings64.sh}
source "$SETTINGS" > /dev/null

cd "$(dirname "$0")"
RTL=../rtl
OUT=build
mkdir -p $OUT
cd $OUT

# fifo.v / dpram.v cannot be elaborated from VHDL with open or unconnected ports in ISim:
# use behavioural VHDL models of them (synthesis keeps the verilog files)
vhpcomp -work work ../fifo_sim.vhd ../dpram_sim.vhd
vhpcomp -work work ../$RTL/spi/spi_slave.vhd ../$RTL/mcu/burst_rx.vhd ../$RTL/mcu/mcu.vhd ../tb_mcu_burst.vhd
fuse -top work.tb_mcu_burst -o tb_mcu_burst.exe

echo "run 2 ms; quit" > run.tcl
./tb_mcu_burst.exe -tclbatch run.tcl | tee sim.log

# any assertion error fails the run
if grep -q "Error:" sim.log; then
	echo "SIMULATION FAILED"
	exit 1
fi
grep -q "tb_mcu_burst: finished" sim.log || { echo "SIMULATION DID NOT FINISH"; exit 1; }
echo "SIMULATION PASSED"
