#!/usr/bin/env python3
# pcf_core.py <in.pcf> <out.pcf>: the constraints of the Mini / Mini G without those of the FT mode of HDMI, for the
# trce of `make <board>-coremode`. In the mode of the core the pixel clock is clk_bus (BUFGMUX I0 of hdmi_pll); in the
# full analysis its flip-flops are also on the FT clock (TS_CLKGEN, and the PERIOD ngdbuild derives from clk_8 and
# the static multiplier of DCM_CLKGEN) and TS_BUS_TO_PIX bounds the paths from clk_bus as asynchronous ones. Without
# them, the paths clk_bus -> pixel clock get the setup and hold of TS_pll_clk_2_, the clock of clk_bus.
import re
import sys

DROP = re.compile(r'^(TS_CLKGEN|TS_BUS_TO_PIX|TS_FT_TO_PIX|TS_hdmi_top_hdmi_pll_(clkgen|clk0|clkfx|clkfx180)(_1)?)$')

text = open(sys.argv[1]).read()
out, dropped = [], []
for m in re.finditer(r'(?ms)^(\S+) = (?:PERIOD|MAXDELAY).*?;\n|^.*?\n', text):
    name = m.group(0).split(' ', 1)[0]
    if m.group(1) and DROP.match(name):
        dropped.append(name)
        continue
    out.append(m.group(0))
if 'TS_CLKGEN' not in dropped or 'TS_BUS_TO_PIX' not in dropped:
    sys.exit('pcf_core.py: TS_CLKGEN / TS_BUS_TO_PIX not found in ' + sys.argv[1])
open(sys.argv[2], 'w').write(''.join(out))
print('pcf_core.py: without ' + ' '.join(dropped))
