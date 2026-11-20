#!/bin/bash
# tb_vga_start_hold (iverilog, seconds): the start hold of the Go VGA (rtl/vga_start_hold.v)
set -e
cd "$(dirname "$0")"
mkdir -p build
iverilog -o build/tb_vga_start_hold tb_vga_start_hold.v ../rtl/vga_start_hold.v
vvp -n build/tb_vga_start_hold | grep -v '\$finish'
