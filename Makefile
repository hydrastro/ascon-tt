# ASCON AEAD for Tiny Tapeout
# ──────────────────────────────────────────────────────────────────────────────
# Standard flow:
#   git clone ... && cd ...
#   git submodule update --init --recursive
#   nix develop              ← enters the shell with all tools
#   make gen-vectors-128a    ← generate test vectors
#   make sim-128a            ← verify RTL (must PASS)
#   make synth-all           ← gate counts for all 4 configs
#   python3 tools/tt15_set_tt_config.py --tiles 8x2 --clock-hz 10000000 --variant 1 --rpc 1
#   make tt12-python-venv    ← one-time venv setup
#   make tt12-harden         ← run LibreLane GDSII flow
#   make tt12-print-stats    ← check results
#   make tt15-find-gds       ← locate the .gds file
# ──────────────────────────────────────────────────────────────────────────────

# ── Tools ─────────────────────────────────────────────────────────────────────
YOSYS    ?= yosys
IVERILOG ?= iverilog
VVP      ?= vvp
VERILATOR?= verilator

# ── Paths ─────────────────────────────────────────────────────────────────────
SRC     := src
TEST    := test
BUILD   := build
SIM_GEN := sim/generated
TT_DIR  := tt
VENV    := .venv
PY      := $(VENV)/bin/python
PDK_ROOT ?= $(CURDIR)/.ttsetup/pdk
PDK      ?= sky130A
LIBRELANE_TAG ?= 3.0.0rc1

# ── Parameters ────────────────────────────────────────────────────────────────
ASCON_VARIANT    ?= 1
ROUNDS_PER_CYCLE ?= 1
USE_SHARED_AEAD  ?= 1
TILES    ?= 8x2
CLOCK_HZ ?= 10000000

# ── Source files ──────────────────────────────────────────────────────────────
CORE_SRC := \
  $(SRC)/ascon_core/ascon_round_comb.v \
  $(SRC)/ascon_core/ascon_perm_unrolled.v \
  $(SRC)/ascon_core/ascon_aead128_enc_ad.v \
  $(SRC)/ascon_core/ascon_aead128_dec_ad.v

ALL_SRC := \
  $(SRC)/project.v \
  $(SRC)/ascon_tt_serial_frontend.v \
  $(SRC)/ascon_tt_aead_core_stub.v \
  $(SRC)/ascon_tt_perm_core.v \
  $(SRC)/ascon_tt_aead_bridge.v \
  $(SRC)/ascon_tt_aead_bridge_dual.v \
  $(SRC)/ascon_tt_aead_shared.v \
  $(CORE_SRC)

TOP := tt_um_ascon_aead

# ── TT environment ─────────────────────────────────────────────────────────────
# LIBRELANE_DOCKERLESS=1 tells librelane to skip container detection.
TT_ENV := \
  PATH=$(CURDIR)/$(VENV)/bin:$(PATH) \
  PDK_ROOT=$(PDK_ROOT) \
  PDK=$(PDK) \
  LIBRELANE_TAG=$(LIBRELANE_TAG) \
  LIBRELANE_DOCKERLESS=1

.PHONY: all help clean tt12-patch-librelane \
  gen-vectors-128a gen-vectors-128 \
  sim-128a sim-128 sim-aead-vectors-shared-prod-directout \
  synth synth-all synth-128a-minarea synth-128a-maxperf synth-128-minarea synth-128-maxperf \
  lint sanity \
  tt5-profiles tt5-report tt5-clean \
  tt12-python-venv tt12-python-check tt12-python-reset \
  tt12-write-user-config tt12-harden \
  tt12-print-warnings tt12-print-stats tt12-create-png \
  tt12-pre-harden-check tt12-print-cell-category \
  tt13-area-report tt15-sweep tt15-find-gds tt16-perf-cost \
  tt17-capture \
  harden-128a-minarea harden-128a-maxperf harden-128-minarea harden-128-maxperf

all: gen-vectors-128a sim-128a

help:
	@echo ""
	@echo "ASCON AEAD for Tiny Tapeout — standard flow:"
	@echo ""
	@echo "  make gen-vectors-128a && make sim-128a   verify RTL (128a)"
	@echo "  make gen-vectors-128  && make sim-128    verify RTL (128)"
	@echo "  make synth-all                           gate counts, all 4 configs"
	@echo "  make tt5-profiles                        structured profile table"
	@echo ""
	@echo "  python3 tools/tt15_set_tt_config.py \\"
	@echo "      --tiles 8x2 --clock-hz 10000000 --variant 1 --rpc 1"
	@echo ""
	@echo "  make tt12-python-venv                    one-time Python setup"
	@echo "  make tt12-harden                         run LibreLane → GDSII"
	@echo "  make tt12-print-stats                    check area/timing"
	@echo "  make tt15-find-gds                       locate .gds file"
	@echo ""
	@echo "  make harden-128a-minarea                 one-shot: 128a, 8x2, 10MHz"
	@echo "  make harden-128a-maxperf                 one-shot: 128a, 10x2, 50MHz"
	@echo "  make harden-128-minarea                  one-shot: 128, 6x2, 10MHz"
	@echo "  make harden-128-maxperf                  one-shot: 128, 8x2, 50MHz"
	@echo ""

$(BUILD):
	mkdir -p $(BUILD)

$(SIM_GEN):
	mkdir -p $(SIM_GEN)

# ── Vector generation ──────────────────────────────────────────────────────────
gen-vectors-128a: | $(SIM_GEN)
	python3 tools/gen_vectors.py --variant 128a $(SIM_GEN)/ascon_aead128_ad_vectors.vh

gen-vectors-128: | $(SIM_GEN)
	python3 tools/gen_vectors.py --variant 128 $(SIM_GEN)/ascon_aead128_ad_vectors.vh

# ── Simulation ─────────────────────────────────────────────────────────────────
$(BUILD)/sim_128a.vvp: $(ALL_SRC) $(TEST)/tb_tt_aead_vectors.v \
    $(SIM_GEN)/ascon_aead128_ad_vectors.vh | $(BUILD)
	$(IVERILOG) -g2005-sv \
	  -I$(SRC) -I$(SRC)/ascon_core -I$(SIM_GEN) \
	  -DASCON_VARIANT_VAL=1 \
	  -P$(TOP).ASCON_VARIANT=1 -P$(TOP).ROUNDS_PER_CYCLE=1 \
	  -P$(TOP).USE_SHARED_AEAD=1 -P$(TOP).ENABLE_PERM_DEBUG=0 \
	  -P$(TOP).ENABLE_DIAGNOSTICS=0 -P$(TOP).ENABLE_OUT_BUFFER=0 \
	  -P$(TOP).MAX_AD_BYTES=32 -P$(TOP).MAX_DATA_BYTES=32 \
	  -o $@ $(TEST)/tb_tt_aead_vectors.v $(ALL_SRC)

$(BUILD)/sim_128.vvp: $(ALL_SRC) $(TEST)/tb_tt_aead_vectors.v \
    $(SIM_GEN)/ascon_aead128_ad_vectors.vh | $(BUILD)
	$(IVERILOG) -g2005-sv \
	  -I$(SRC) -I$(SRC)/ascon_core -I$(SIM_GEN) \
	  -DASCON_VARIANT_VAL=0 \
	  -P$(TOP).ASCON_VARIANT=0 -P$(TOP).ROUNDS_PER_CYCLE=1 \
	  -P$(TOP).USE_SHARED_AEAD=1 -P$(TOP).ENABLE_PERM_DEBUG=0 \
	  -P$(TOP).ENABLE_DIAGNOSTICS=0 -P$(TOP).ENABLE_OUT_BUFFER=0 \
	  -P$(TOP).MAX_AD_BYTES=32 -P$(TOP).MAX_DATA_BYTES=32 \
	  -o $@ $(TEST)/tb_tt_aead_vectors.v $(ALL_SRC)

sim-128a: gen-vectors-128a $(BUILD)/sim_128a.vvp
	$(VVP) $(BUILD)/sim_128a.vvp

sim-128: gen-vectors-128 $(BUILD)/sim_128.vvp
	$(VVP) $(BUILD)/sim_128.vvp

# Guide alias
sim-aead-vectors-shared-prod-directout: sim-128a

# ── Synthesis ───────────────────────────────────────────────────────────────────
synth: $(ALL_SRC) | $(BUILD)
	$(YOSYS) -p " \
	  read_verilog $(ALL_SRC); \
	  chparam -set ASCON_VARIANT $(ASCON_VARIANT) \
	          -set ROUNDS_PER_CYCLE $(ROUNDS_PER_CYCLE) \
	          -set USE_SHARED_AEAD $(USE_SHARED_AEAD) $(TOP); \
	  synth -top $(TOP); check; stat" \
	  | tee $(BUILD)/synth_V$(ASCON_VARIANT)_R$(ROUNDS_PER_CYCLE).log

synth-128a-minarea: ; $(MAKE) synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1
synth-128a-maxperf: ; $(MAKE) synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=8
synth-128-minarea:  ; $(MAKE) synth ASCON_VARIANT=0 ROUNDS_PER_CYCLE=1
synth-128-maxperf:  ; $(MAKE) synth ASCON_VARIANT=0 ROUNDS_PER_CYCLE=8

synth-all:
	$(MAKE) synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1
	$(MAKE) synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=8
	$(MAKE) synth ASCON_VARIANT=0 ROUNDS_PER_CYCLE=1
	$(MAKE) synth ASCON_VARIANT=0 ROUNDS_PER_CYCLE=8

# ── Lint ────────────────────────────────────────────────────────────────────────
lint:
	$(VERILATOR) --lint-only -Wall -Wno-DECLFILENAME -Wno-UNUSEDPARAM \
	  -DASCON_VARIANT=$(ASCON_VARIANT) -DROUNDS_PER_CYCLE=$(ROUNDS_PER_CYCLE) \
	  -I$(SRC) -I$(SRC)/ascon_core \
	  --top-module $(TOP) $(ALL_SRC)

sanity: | $(BUILD)
	$(YOSYS) -q -p " \
	  read_verilog $(ALL_SRC); \
	  chparam -set ASCON_VARIANT $(ASCON_VARIANT) \
	          -set ROUNDS_PER_CYCLE $(ROUNDS_PER_CYCLE) $(TOP); \
	  synth -top $(TOP); check" \
	  && echo "Sanity OK"

# ── Profile matrix ──────────────────────────────────────────────────────────────
$(BUILD)/tt5:
	mkdir -p $(BUILD)/tt5

tt5-clean:
	rm -rf $(BUILD)/tt5

tt5-profiles: $(ALL_SRC) | $(BUILD)/tt5
	python3 tools/tt5_run_profiles.py --out-dir $(BUILD)/tt5
	python3 tools/report_tt5_profiles.py $(BUILD)/tt5/v*.txt

tt5-report:
	python3 tools/report_tt5_profiles.py $(BUILD)/tt5/v*.txt

# ── Python venv ────────────────────────────────────────────────────────────────
tt12-python-venv:
	@test -f $(TT_DIR)/requirements.txt || \
	  { echo "ERROR: tt/ submodule not checked out."; \
	    echo "Run: git submodule update --init --recursive"; exit 1; }
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip
	$(VENV)/bin/pip install -r $(TT_DIR)/requirements.txt
	$(VENV)/bin/pip install "librelane==$(LIBRELANE_TAG)"
	@echo "Venv ready."

tt12-python-check:
	@test -x $(PY) || { echo "ERROR: run 'make tt12-python-venv' first"; exit 1; }
	$(PY) -c "import chevron, yaml, git, librelane; print('Python env OK')"
	$(TT_ENV) command -v yowasp-yosys
	$(TT_ENV) $(PY) ./$(TT_DIR)/tt_tool.py --help >/dev/null 2>&1
	@echo "tt12-python-check OK"

tt12-python-reset:
	rm -rf $(VENV)

# ── Write user_config.json (bypasses broken tt_tool.py --create-user-config) ──
# tt_tool.py --create-user-config fails because it runs yosys without -D defines.
# We generate user_config.json directly from src/config.json instead.
tt12-write-user-config:
	python3 tools/write_user_config.py

# ── Harden ─────────────────────────────────────────────────────────────────────
# Calls tt_tool.py --harden which drives the full LibreLane/OpenLane2 flow.
# Requires: nix develop (for tkinter), make tt12-python-venv, PDK installed.
# Patch librelane to use tclsh instead of tkinter (safe no-op if already patched)
tt12-patch-librelane:
	python3 tools/patch_librelane_tcl.py

tt12-harden: tt12-write-user-config tt12-patch-librelane
	$(TT_ENV) $(PY) -m librelane --pdk-root $(PDK_ROOT) --pdk $(PDK) --force-run-dir runs/wokwi src/config.json

# ── Post-harden inspection ─────────────────────────────────────────────────────
tt12-print-warnings:
	@echo "=== Warnings from last harden run ==="
	@find runs/wokwi -name "*.log" -newer src/config.json 2>/dev/null \
	  | xargs grep -l -i "warning" 2>/dev/null \
	  | while read f; do echo "--- $$f ---"; grep -i "warning" "$$f" | tail -5; done || true
	@python3 tools/post_harden.py runs/wokwi

tt12-print-stats:
	python3 tools/post_harden.py runs/wokwi

tt12-print-cell-category:
	@find runs/wokwi -name "metrics.json" 2>/dev/null | sort | tail -1 \
	  | xargs python3 -c "import json,sys; m=json.load(open(sys.argv[1])); \
	    [print(k,v) for k,v in m.items() if 'cell' in k.lower()]" 2>/dev/null || \
	  echo "No metrics.json found — run make tt12-harden first." 

tt12-create-png:
	@GDS=$$(find runs/wokwi -name "*.gds" 2>/dev/null | sort | tail -1); \
	 if [ -n "$$GDS" ]; then \
	   echo "Generating PNG from $$GDS ..."; \
	   $(TT_ENV) $(PY) ./$(TT_DIR)/tt_tool.py --create-png 2>/dev/null || \
	   python3 tools/tt17_klayout_screenshot.py "$$GDS" 2>/dev/null || \
	   echo "PNG generation requires klayout or tt_tool.py — skipping."; \
	 else \
	   echo "No GDS found — run make tt12-harden first."; \
	 fi

tt12-pre-harden-check: tt12-python-check
	$(MAKE) synth ASCON_VARIANT=$(ASCON_VARIANT) ROUNDS_PER_CYCLE=$(ROUNDS_PER_CYCLE)
	@echo "pre-harden checks passed"

# ── Find GDS ───────────────────────────────────────────────────────────────────
tt15-find-gds:
	@echo "=== GDS / DEF files from last harden run ==="
	@find runs -name "*.gds" -o -name "*.gds.gz" 2>/dev/null | sort | tail -10 || true
	@echo ""
	@find runs -name "*.def" 2>/dev/null | grep -v "/.tmp" | sort | tail -5 || true

# ── Tile/frequency sweep ───────────────────────────────────────────────────────
tt15-sweep:
	TT_SWEEP_TILES="$${TT_SWEEP_TILES:-8x2 6x2 10x2}" \
	TT_SWEEP_FREQS="$${TT_SWEEP_FREQS:-10000000 25000000 50000000}" \
	./tools/tt15_tile_freq_sweep.sh

# ── Area report (after hardening) ─────────────────────────────────────────────
$(BUILD)/tt13:
	mkdir -p $(BUILD)/tt13

tt13-area-report: | $(BUILD)/tt13
	python3 tools/post_harden.py runs/wokwi

# ── Perf/cost model (informational only) ──────────────────────────────────────
tt16-perf-cost: | $(BUILD)
	python3 tools/perf_cost_estimate.py
# ── Capture artifact ───────────────────────────────────────────────────────────
NAME ?= run
tt17-capture:
	./tools/tt17_capture_harden.sh \
	  --tiles $(TILES) \
	  --clock-hz $(CLOCK_HZ) \
	  --store production \
	  --name "$(NAME)" \
	  $(if $(ALLOW_DIRTY),--allow-dirty,)

# ── Four one-shot harden targets ───────────────────────────────────────────────
# Each: sets config, writes user_config, hardens.
harden-128a-minarea:
	python3 tools/tt15_set_tt_config.py --tiles 8x2  --clock-hz 10000000 --variant 1 --rpc 1
	$(MAKE) tt12-harden ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1

harden-128a-maxperf:
	python3 tools/tt15_set_tt_config.py --tiles 10x2 --clock-hz 50000000 --variant 1 --rpc 8
	$(MAKE) tt12-harden ASCON_VARIANT=1 ROUNDS_PER_CYCLE=8

harden-128-minarea:
	python3 tools/tt15_set_tt_config.py --tiles 6x2  --clock-hz 10000000 --variant 0 --rpc 1
	$(MAKE) tt12-harden ASCON_VARIANT=0 ROUNDS_PER_CYCLE=1

harden-128-maxperf:
	python3 tools/tt15_set_tt_config.py --tiles 8x2  --clock-hz 50000000 --variant 0 --rpc 8
	$(MAKE) tt12-harden ASCON_VARIANT=0 ROUNDS_PER_CYCLE=8

# ── Clean ──────────────────────────────────────────────────────────────────────
clean:
	rm -rf $(BUILD) $(SIM_GEN)
