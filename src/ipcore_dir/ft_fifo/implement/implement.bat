:: (c) Copyright 2009 - 2010 Xilinx, Inc. All rights reserved.
:: 
:: This file contains confidential and proprietary information
:: of Xilinx, Inc. and is protected under U.S. and
:: international copyright and other intellectual property
:: laws.
:: 
:: DISCLAIMER
:: This disclaimer is not a license and does not grant any
:: rights to the materials distributed herewith. Except as
:: otherwise provided in a valid license issued to you by
:: Xilinx, and to the maximum extent permitted by applicable
:: law: (1) THESE MATERIALS ARE MADE AVAILABLE "AS IS" AND
:: WITH ALL FAULTS, AND XILINX HEREBY DISCLAIMS ALL WARRANTIES
:: AND CONDITIONS, EXPRESS, IMPLIED, OR STATUTORY, INCLUDING
:: BUT NOT LIMITED TO WARRANTIES OF MERCHANTABILITY, NON-
:: INFRINGEMENT, OR FITNESS FOR ANY PARTICULAR PURPOSE; and
:: (2) Xilinx shall not be liable (whether in contract or tort,
:: including negligence, or under any other theory of
:: liability) for any loss or damage of any kind or nature
:: related to, arising under or in connection with these
:: materials, including for any direct, or any indirect,
:: special, incidental, or consequential loss or damage
:: (including loss of data, profits, goodwill, or any type of
:: loss or damage suffered as a result of any action brought
:: by a third party) even if such damage or loss was
:: reasonably foreseeable or Xilinx had been advised of the
:: possibility of the same.
:: 
:: CRITICAL APPLICATIONS
:: Xilinx products are not designed or intended to be fail-
:: safe, or for use in any application requiring fail-safe
:: performance, such as life-support or safety devices or
:: systems, Class III medical devices, nuclear facilities,
:: applications related to the deployment of airbags, or any
:: other applications that could lead to death, personal
:: injury, or severe property or environmental damage
:: (individually and collectively, "Critical
:: Applications"). Customer assumes the sole risk and
:: liability of any use of Xilinx products in Critical
:: Applications, subject only to applicable laws and
:: regulations governing limitations on product liability.
:: 
:: THIS COPYRIGHT NOTICE AND DISCLAIMER MUST BE RETAINED AS
:: PART OF THIS FILE AT ALL TIMES.

rem Clean up the results directory
rmdir /S /Q results
mkdir results

rem Synthesize the VHDL Wrapper Files

#Synthesize the Wrapper Files

echo 'Synthesizing example design with XST';
xst -ifn xst.scr
copy ft_fifo_exdes.ngc .\results\


rem Copy the netlist generated by Coregen
echo 'Copying files from the netlist directory to the results directory'
copy ..\..\ft_fifo.ngc results\


rem  Copy the constraints files generated by Coregen
echo 'Copying files from constraints directory to results directory'
copy ..\example_design\ft_fifo_exdes.ucf results\

cd results

echo 'Running ngdbuild'

ngdbuild -p xc6slx25-ftg256-2 -sd ../../../ ft_fifo_exdes

echo 'Running map'
map ft_fifo_exdes -o mapped.ncd

echo 'Running par'
par mapped.ncd routed.ncd

echo 'Running trce'
trce -e 10 routed.ncd mapped.pcf -o routed

echo 'Running design through bitgen'
bitgen -w routed

echo 'Running netgen to create gate level Verilog model'
netgen -ofmt verilog -sim -tm ft_fifo_exdes -pcf mapped.pcf -w -sdf_anno false routed.ncd routed.v
