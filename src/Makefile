# Command line build of the TS-Conf core for the three boards: the steps and options of the ISE 14.7
# project navigator (the .xise projects of the boards, removed when this Makefile replaced them).
#
#   make                 all three boards (tsconf.kg1, tsconf.kg2, tsconf.kg3)
#   make go|mini|minig   one board: synthesis, implementation, bitstream, .kg file
#   make minig-xst       one step: <board>-xst (.ngc), <board>-impl (.bin), <board>-core (.kg)
#   make minig-report    LUTs, slices, block RAMs and the timing result of the last build (and of -coremode)
#   make minig-coremode  the timing of the last build in the mode of the core of HDMI (Mini, Mini G; see below)
#   make clean           the intermediate files (not the .bin / .kg files, they are in git)
#
# Inputs per board: karabas_<board>.prj (the source list, the shared modules as
# "../modules/rtl/..."), .xst, .ucf, .ut.
# A step runs again when one of its inputs is newer than its output.
# The boards share xst/ and _ngo/, so they are built one after the other.

ISE_SETTINGS ?= /opt/Xilinx/14.7/ISE_DS/settings64.sh
PART = xc6slx25-ftg256-2
BOARDS = go mini minig

SHELL = /bin/bash
.SHELLFLAGS = -e -o pipefail -c
.NOTPARALLEL:
# settings64.sh takes the arguments of the shell that sources it: none here
XIL = source $(ISE_SETTINGS) > /dev/null;

KG_go = tsconf.kg1
KG_mini = tsconf.kg2
KG_minig = tsconf.kg3
JSON_go = core.json
JSON_mini = core_mini.json
JSON_minig = core_minig.json

# map / par options (as the .xise projects had them, the same for the three boards but the cost table)
# The cost table (map -t, the placement seed) of the Mini is 2: with 1 the placement of the build of 2026-10-19
# put a shift register of the 5x clock of zhdmi far from its OSERDES (-0.21 ns); 2, 3, 4 met all constraints.
MAP_T_go = 1
MAP_T_mini = 2
MAP_T_minig = 1
MAP_OPT = -logic_opt off -ol high -xe n -xt 0 -register_duplication off -r 4 -global_opt off -mt 2 -detail -ir off -pr b -lc off -power off
PAR_OPT = -ol high -xe n -mt 4

# included or read by the sources, not in the prj
INCLUDES = $(wildcard ../modules/rtl/mcu/*.vh rtl/vg93/*.vh) rtl/tune.v rtl/tsconf/video/video_cram.mif rtl/sound/saa1099_compressor_lut.hex

.PHONY: all clean $(BOARDS) $(BOARDS:=-xst) $(BOARDS:=-impl) $(BOARDS:=-core) $(BOARDS:=-report) mini-coremode minig-coremode

# The pixel clock of HDMI (Mini, Mini G) is a BUFGMUX of clk_bus and the FT812 clock: its flip-flops are on both,
# and the ucf bounds the paths from clk_bus as asynchronous ones (TS_BUS_TO_PIX). <board>-coremode runs trce again
# without the constraints of the FT mode (pcf_core.py): the paths clk_bus -> pixel clock with the setup and hold of
# clk_bus, as they are in the mode of the core. Run it after every build of these boards.

all: $(BOARDS)

define board
SRC_$(1) := $$(shell sed -n 's/^[a-z]* work "\(.*\)"/\1/p' karabas_$(1).prj)

karabas_$(1).ngc: karabas_$(1).prj karabas_$(1).xst $$(SRC_$(1)) $(INCLUDES)
	mkdir -p xst/projnav.tmp
	$(XIL) xst -intstyle ise -ifn karabas_$(1).xst -ofn karabas_$(1).syr

karabas_$(1).bin: karabas_$(1).ngc karabas_$(1).ucf karabas_$(1).ut
	$(XIL) ngdbuild -intstyle ise -dd _ngo -nt timestamp -uc karabas_$(1).ucf -p $(PART) karabas_$(1).ngc karabas_$(1).ngd
	$(XIL) map -intstyle ise -p $(PART) -w $(MAP_OPT) -t $(MAP_T_$(1)) -o karabas_$(1)_map.ncd karabas_$(1).ngd karabas_$(1).pcf
	$(XIL) par -w -intstyle ise $(PAR_OPT) karabas_$(1)_map.ncd karabas_$(1).ncd karabas_$(1).pcf
	$(XIL) trce -intstyle ise -v 3 -s 2 -n 3 -fastpaths -xml karabas_$(1).twx karabas_$(1).ncd -o karabas_$(1).twr karabas_$(1).pcf -ucf karabas_$(1).ucf
	$(XIL) bitgen -intstyle ise -f karabas_$(1).ut karabas_$(1).ncd

$(KG_$(1)): karabas_$(1).bin $(JSON_$(1)) $$(wildcard roms/*)
	python3 make_core.py $(JSON_$(1)) $$@

$(1): $(KG_$(1))
$(1)-xst: karabas_$(1).ngc
$(1)-impl: karabas_$(1).bin
$(1)-core: $(KG_$(1))
$(1)-report:
	@grep -E "Number of (Slice LUTs|occupied Slices|RAMB16BWERs|RAMB8BWERs):" karabas_$(1)_map.mrp
	@grep -E "constraints? (was|were) met|constraints? not met|Timing Score" karabas_$(1).par | sort -u
	@if [ -f karabas_$(1)_core.twr ]; then echo "mode of the core (-coremode):"; \
		grep -E "constraints? (was|were) met|constraints? not met|Timing errors" karabas_$(1)_core.twr | sort -u; fi
endef

$(foreach b,$(BOARDS),$(eval $(call board,$(b))))

define core_mode
$(1)-coremode: karabas_$(1)_core.twr
karabas_$(1)_core.twr: karabas_$(1).bin pcf_core.py
	python3 pcf_core.py karabas_$(1).pcf karabas_$(1)_core.pcf
	$(XIL) trce -intstyle ise -v 3 -s 2 -n 3 -fastpaths karabas_$(1).ncd -o karabas_$(1)_core.twr karabas_$(1)_core.pcf \
		| tee karabas_$(1)_core.log | grep -E "ERROR|WARNING" || true
	@! grep -q "No timing constraints found" karabas_$(1)_core.twr || { echo "trce did not read karabas_$(1)_core.pcf"; \
		rm -f karabas_$(1)_core.twr; exit 1; }
endef
$(foreach b,mini minig,$(eval $(call core_mode,$(b))))

clean:
	rm -rf xst _ngo _xmsgs xlnx_auto_0_xdb iseconfig
	rm -f $(foreach b,$(BOARDS),$(addprefix karabas_$(b),.ngc .ngd .ngr .syr .lso .bld .pcf .ncd _map.ncd _map.ngm \
		_map.map _map.mrp _map.xrpt .par .pad _pad.csv _pad.txt .twr .twx .unroutes .xpi .ptwx .bgn .bit .drc \
		_bitgen.xwbt _summary.xml _usage.xml _xst.xrpt _ngdbuild.xrpt _par.xrpt _guide.ncd _core.pcf _core.twr _core.log))
