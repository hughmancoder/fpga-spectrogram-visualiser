# ==============================================================================
# Makefile for Tang Nano 20K (Gowin GW2AR-LV18)
# Supports OSS CAD Suite (Yosys, nextpnr-himbaechel, Apicula/gowin_pack, openFPGALoader)
# ==============================================================================

PROJECT    ?= top
DEVICE     ?= GW2AR-LV18QN88C8/I7
FAMILY     ?= GW2A-18C
BOARD      ?= tangnano20k

PKG_SRCS   := $(wildcard src/*_pkg.sv)
RTL_SRCS   := $(filter-out $(PKG_SRCS),$(wildcard src/*.sv))

SRCS       ?= $(PKG_SRCS) $(RTL_SRCS)
CST        ?= constraints/tangnano20k.cst

# Timing target for place and route in MHz (fastest clock, the 74.25 MHz pixel clock)
PNR_FREQ   ?= 74.25

# Testbench selection (e.g. make sim TB=top_tb or make sim TB=video_sync_tb)
TB         ?= top_tb
TB_NAME    := $(notdir $(basename $(TB)))
ifeq ($(suffix $(TB)),.sv)
    TB_FILE := $(TB)
else
    TB_FILE := sim/$(TB_NAME).sv
endif
SIM_MODELS ?= sim/gowin_sim.sv
TB_SRCS    := $(SIM_MODELS) $(PKG_SRCS) $(RTL_SRCS) $(TB_FILE)

# Extra iverilog flags
TB_PARAMS  ?=

# Regression test list for `make test`
TESTS      ?= video_sync_tb hdmi_clock_gen_tb spectrum_pattern_gen_tb bar_renderer_tb i2s_rx_tb fft_tb top_tb

BUILD_DIR  ?= build

# Auto-detect OSS CAD Suite path if installed in standard locations
OSS_CAD_PATHS := $(HOME)/oss-cad-suite/bin /opt/oss-cad-suite/bin $(CURDIR)/.toolchain/oss-cad-suite/bin
FOUND_OSS_CAD := $(firstword $(wildcard $(OSS_CAD_PATHS)))
ifneq ($(FOUND_OSS_CAD),)
    export PATH := $(FOUND_OSS_CAD):$(PATH)
    CAD_BIN     := $(FOUND_OSS_CAD)/
else
    CAD_BIN     :=
endif

# Toolchain executables (resolves to CAD_BIN full path if OSS CAD Suite is detected)
YOSYS           ?= $(CAD_BIN)yosys
GOWIN_PACK      ?= $(CAD_BIN)gowin_pack
OPENFPGALOADER  ?= $(CAD_BIN)openFPGALoader
IVERILOG        ?= $(CAD_BIN)iverilog
VVP             ?= $(CAD_BIN)vvp
GTKWAVE         ?= $(CAD_BIN)gtkwave

# Detect nextpnr flavor: nextpnr-himbaechel is preferred for GW2A/GW2AR
ifneq ($(wildcard $(CAD_BIN)nextpnr-himbaechel),)
    PNR := $(CAD_BIN)nextpnr-himbaechel
    PNR_FLAGS := --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST)
else ifneq ($(wildcard $(CAD_BIN)nextpnr-gowin),)
    PNR := $(CAD_BIN)nextpnr-gowin
    PNR_FLAGS := --device $(DEVICE) --cst $(CST)
else ifneq ($(shell which nextpnr-himbaechel 2>/dev/null),)
    PNR := nextpnr-himbaechel
    PNR_FLAGS := --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST)
else ifneq ($(shell which nextpnr-gowin 2>/dev/null),)
    PNR := nextpnr-gowin
    PNR_FLAGS := --device $(DEVICE) --cst $(CST)
else
    PNR := $(CAD_BIN)nextpnr-himbaechel
    PNR_FLAGS := --device $(DEVICE) --vopt family=$(FAMILY) --vopt cst=$(CST)
endif

# Output artifacts
JSON       := $(BUILD_DIR)/$(PROJECT).json
PNR_JSON   := $(BUILD_DIR)/$(PROJECT)_pnr.json
BITSTREAM  := $(BUILD_DIR)/$(PROJECT).fs
SIM_VVP    := $(BUILD_DIR)/$(TB_NAME).vvp
VCD_FILE   := $(BUILD_DIR)/$(TB_NAME).vcd

# Default target
.PHONY: all
all: bitstream

# Help target
.PHONY: help
help:
	@echo "Tang Nano 20K FPGA Build System (macOS / Linux)"
	@echo "----------------------------------------------------"
	@echo "  make             - Build the complete bitstream ($(BITSTREAM))"
	@echo "  make synth       - Run synthesis with Yosys"
	@echo "  make pnr         - Run Place & Route with $(PNR)"
	@echo "  make pack        - Pack into Gowin bitstream (.fs)"
	@echo "  make flash-sram  - Fast upload directly to FPGA SRAM (non-persistent)"
	@echo "  make flash       - Program onboard SPI Flash (persistent across reboot)"
	@echo "  make sim         - Run default simulation (sim/top_tb.v)"
	@echo "  make sim TB=name - Run specific testbench (e.g. TB=top_tb or TB=sim/my_tb.v)"
	@echo "  make waves       - Open simulation waveforms in GTKWave / Surfer (supports TB=name)"
	@echo "  make test        - Run regression testbenches ($(TESTS))"
	@echo "  make format      - Auto-format all SystemVerilog files in src/ and sim/"
	@echo "  make diagram     - Generate block diagrams for top, fft and bar_renderer ($(DIAGRAM_DIR))"
	@echo "  make diagram-module MODULE=name - Generate gate-level schematic in $(BUILD_DIR)/"
	@echo "  make clean       - Clean all build & simulation artifacts"
	@echo "  make clean-sim   - Clean only simulation artifacts (.vvp, .vcd, logs)"
	@echo "  make check-tools - Verify toolchain installation status"
	@echo "  make setup-toolchain - Download & install OSS CAD Suite for macOS"

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

# ------------------------------------------------------------------------------
# 1. Synthesis (Yosys)
# ------------------------------------------------------------------------------
.PHONY: synth
synth: $(JSON)

$(JSON): $(SRCS) | $(BUILD_DIR)
	@echo "==> Synthesizing with Yosys..."
	$(YOSYS) -p "read_verilog -sv $(SRCS); synth_gowin -top $(PROJECT) -json $(JSON)"

# ------------------------------------------------------------------------------
# 2. Place & Route (nextpnr-himbaechel / nextpnr-gowin)
# ------------------------------------------------------------------------------
.PHONY: pnr
pnr: $(PNR_JSON)

$(PNR_JSON): $(JSON) $(CST)
	@echo "==> Running Place & Route with $(PNR)..."
	$(PNR) --json $(JSON) --write $(PNR_JSON) --freq $(PNR_FREQ) $(PNR_FLAGS)

# ------------------------------------------------------------------------------
# 3. Bitstream Generation (gowin_pack / Apicula)
# ------------------------------------------------------------------------------
.PHONY: bitstream pack
bitstream: $(BITSTREAM)
pack: $(BITSTREAM)

$(BITSTREAM): $(PNR_JSON)
	@echo "==> Generating Gowin bitstream (.fs)..."
	$(GOWIN_PACK) -d $(FAMILY) -o $(BITSTREAM) $(PNR_JSON)
	@echo "==> Bitstream successfully created: $(BITSTREAM)"

# ------------------------------------------------------------------------------
# 4. Programming / Flashing (openFPGALoader)
# ------------------------------------------------------------------------------
# Fast SRAM download for rapid test iteration
.PHONY: flash-sram load
flash-sram load: $(BITSTREAM)
	@echo "==> Loading bitstream into FPGA SRAM (fast, volatile)..."
	$(OPENFPGALOADER) -b $(BOARD) $(BITSTREAM)

# Program onboard SPI flash for persistent boot
.PHONY: flash flash-flash
flash flash-flash: $(BITSTREAM)
	@echo "==> Programming bitstream to onboard Flash (persistent)..."
	$(OPENFPGALOADER) -b $(BOARD) -f $(BITSTREAM)

# ------------------------------------------------------------------------------
# 5. Simulation & Waveform Viewing (iverilog + vvp)
# ------------------------------------------------------------------------------
.PHONY: sim waves test FORCE
sim: $(SIM_VVP)
	@echo "==> Running simulation ($(TB_NAME))..."
	$(VVP) $(SIM_VVP)

# Always recompile: REF / TB_PARAMS can change without any file changing
$(SIM_VVP): $(TB_SRCS) FORCE | $(BUILD_DIR)
	@echo "==> Compiling testbench $(TB_FILE) with iverilog..."
	$(IVERILOG) -g2012 $(TB_PARAMS) -o $(SIM_VVP) -s $(TB_NAME) $(TB_SRCS)

FORCE:

# Regression: each testbench prints "TEST PASSED" or "TEST FAILED"
test: | $(BUILD_DIR)
	@pass=0; fail=0; \
	for t in $(TESTS); do \
		echo "==> $$t"; \
		if $(MAKE) --no-print-directory sim TB=$$t VVP="$(VVP)" \
		     > $(BUILD_DIR)/$$t.log 2>&1 && grep -qiE "TEST PASSED|ALL CHECKS PASSED|ALL TESTS PASSED" $(BUILD_DIR)/$$t.log; then \
			echo "    PASS"; pass=$$((pass+1)); \
		else \
			echo "    FAIL (see $(BUILD_DIR)/$$t.log)"; fail=$$((fail+1)); \
			grep -E "FAIL|ERROR|error" $(BUILD_DIR)/$$t.log | head -5 | sed 's/^/      /'; \
		fi; \
	done; \
	echo "==> $$pass passed, $$fail failed"; \
	test $$fail -eq 0

waves: sim
	@echo "==> Opening waveform in viewer..."
	@if [ -x "$(GTKWAVE)" ] || command -v $(GTKWAVE) >/dev/null 2>&1; then \
		$(GTKWAVE) $(VCD_FILE); \
	elif command -v surfer >/dev/null 2>&1; then \
		surfer $(VCD_FILE); \
	else \
		echo "Neither gtkwave nor surfer found. Please install via: brew install --cask gtkwave"; \
	fi

# ------------------------------------------------------------------------------
# 6. Toolchain Check & Automated Installer
# ------------------------------------------------------------------------------
.PHONY: check-tools
check-tools:
	@echo "Checking toolchain components..."
	@printf "%-20s: " "yosys" && (which $(YOSYS) 2>/dev/null || echo "MISSING")
	@printf "%-20s: " "pnr" && (which $(PNR) 2>/dev/null || echo "MISSING")
	@printf "%-20s: " "gowin_pack" && (which $(GOWIN_PACK) 2>/dev/null || echo "MISSING")
	@printf "%-20s: " "openFPGALoader" && (which $(OPENFPGALOADER) 2>/dev/null || echo "MISSING")
	@printf "%-20s: " "iverilog" && (which $(IVERILOG) 2>/dev/null || echo "MISSING")
	@printf "%-20s: " "vvp" && (which $(VVP) 2>/dev/null || echo "MISSING")

.PHONY: setup-toolchain
setup-toolchain:
	@chmod +x scripts/setup_toolchain.sh
	@./scripts/setup_toolchain.sh

.PHONY: format
format:
	@echo "==> Formatting SystemVerilog files with verible-verilog-format..."
	verible-verilog-format --indentation_spaces=4 --named_port_alignment=align --port_declarations_alignment=flush-left --module_net_variable_alignment=flush-left --inplace src/*.sv sim/*.sv
	verible-verilog-syntax src/*.sv sim/*.sv

# Block diagrams with square wiring (requires netlistsvg, see README).
# Small logic in top is grouped into named blocks so only modules are drawn.
DIAGRAM_DIR ?= docs/images/diagrams

.PHONY: diagram
diagram: | $(BUILD_DIR)
	@echo "==> Generating block diagrams in $(DIAGRAM_DIR) with Yosys and netlistsvg..."
	$(YOSYS) -q -p "read_verilog -sv -nomem2reg $(SRCS); hierarchy -top top; proc; memory_collect; opt_clean; submod -name video_sync_delay top/t:\$$adff; submod -name display_bars top/t:\$$mem_v2 top/t:\$$mux top/t:\$$dff; opt_clean; write_json $(BUILD_DIR)/top_diagram.json"
	python3 scripts/draw_diagram.py top src/top.sv $(BUILD_DIR)/top_diagram.json $(DIAGRAM_DIR)/top_diagram.svg
	$(YOSYS) -q -p "read_verilog -sv -nomem2reg src/fft.sv; hierarchy -top fft; proc; memory_collect; opt_clean; write_json $(BUILD_DIR)/fft_diagram.json"
	python3 scripts/draw_diagram.py fft src/fft.sv $(BUILD_DIR)/fft_diagram.json $(DIAGRAM_DIR)/fft_diagram.svg
	$(YOSYS) -q -p "read_verilog -sv -nomem2reg src/bar_renderer.sv; hierarchy -top bar_renderer; proc; memory_collect; opt_clean; write_json $(BUILD_DIR)/bar_renderer_diagram.json"
	python3 scripts/draw_diagram.py bar_renderer src/bar_renderer.sv $(BUILD_DIR)/bar_renderer_diagram.json $(DIAGRAM_DIR)/bar_renderer_diagram.svg

# Gate-level schematic of one module, e.g. make diagram-module MODULE=fft (requires Graphviz)
MODULE     ?= top

.PHONY: diagram-module
diagram-module: | $(BUILD_DIR)
	$(YOSYS) -q -p "read_verilog -sv -nomem2reg $(SRCS); hierarchy -top $(MODULE); proc; memory_collect; opt_clean; show -format svg -prefix $(BUILD_DIR)/$(MODULE)_schematic -notitle -width $(MODULE)"
	@rm -f $(BUILD_DIR)/$(MODULE)_schematic.dot

# ------------------------------------------------------------------------------
# 7. Clean Targets
# ------------------------------------------------------------------------------
.PHONY: clean clean-sim clean-all distclean
clean:
	@echo "==> Cleaning build artifacts..."
	@rm -rf $(BUILD_DIR) *.vcd *.vvp *.fs *.json *.log sim/*.vcd sim/*.vvp sim/*.log

clean-sim:
	@echo "==> Cleaning simulation artifacts..."
	@rm -rf $(BUILD_DIR)/*.vcd $(BUILD_DIR)/*.vvp $(BUILD_DIR)/*.log *.vcd *.vvp *.log sim/*.vcd sim/*.vvp sim/*.log

clean-all distclean: clean
	@echo "==> Cleaning all generated files..."
	@rm -rf $(BUILD_DIR) .toolchain/
