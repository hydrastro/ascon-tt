# ASCON AEAD for Tiny Tapeout
# Four GDSII configurations:
#   ascon128a-minarea   ASCON-128a, 1 round/cycle, 6×2 tiles, 10 MHz
#   ascon128a-maxperf   ASCON-128a, 8 rounds/cycle, 8×2 tiles, 50 MHz
#   ascon128-minarea    ASCON-128,  1 round/cycle, 4×2 tiles, 10 MHz
#   ascon128-maxperf    ASCON-128,  8 rounds/cycle, 6×2 tiles, 50 MHz
#
# Quickstart (inside nix develop):
#   make gen-vectors-128a            # generate ASCON-128a test vectors
#   make sim-128a                    # functional sim (ASCON-128a)
#   make synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1   # gate count
#   make tt12-python-venv            # build Python venv (once)
#   make harden-128a-minarea         # generate GDSII

# ── Tools ─────────────────────────────────────────────────────────────────
YOSYS    ?= yosys
IVERILOG ?= iverilog
VVP      ?= vvp

# ── Paths ─────────────────────────────────────────────────────────────────
SRC      := src
TEST     := test
BUILD    := build
SIM_GEN  := sim/generated
TT_DIR   := tt
VENV     := .venv

# ── Parameters (override on CLI) ──────────────────────────────────────────
ASCON_VARIANT    ?= 1   # 0=ASCON-128, 1=ASCON-128a
ROUNDS_PER_CYCLE ?= 1   # 1=min-area, 8=max-perf
USE_SHARED_AEAD  ?= 1   # 1=shared, 0=dual-path reference

# ── Source files ──────────────────────────────────────────────────────────
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

# ── TT tooling env ────────────────────────────────────────────────────────
PDK_ROOT        ?= $(CURDIR)/.ttsetup/pdk
PDK             ?= sky130A
LIBRELANE_TAG   ?= 3.0.0rc1

TT_ENV := \
  PATH=$(CURDIR)/$(VENV)/bin:$(PATH) \
  PDK_ROOT=$(PDK_ROOT) \
  PDK=$(PDK) \
  LIBRELANE_TAG=$(LIBRELANE_TAG) \
  LIBRELANE_DOCKERLESS=1

PY := $(VENV)/bin/python

# ── Phony ─────────────────────────────────────────────────────────────────
.PHONY: all help clean \
  gen-vectors-128a gen-vectors-128 \
  sim-128a sim-128 \
  synth synth-all \
  tt5-profiles \
  tt12-python-venv tt12-python-check tt12-python-reset \
  tt12-create-user-config tt12-harden \
  tt12-print-warnings tt12-print-stats tt12-create-png \
  harden-128a-minarea harden-128a-maxperf \
  harden-128-minarea  harden-128-maxperf

all: gen-vectors-128a sim-128a

help:
	@echo ""
	@echo "ASCON AEAD for Tiny Tapeout"
	@echo ""
	@echo "Simulation:"
	@echo "  make gen-vectors-128a     generate ASCON-128a test vectors"
	@echo "  make gen-vectors-128      generate ASCON-128 test vectors"
	@echo "  make sim-128a             ASCON-128a functional test (shared core)"
	@echo "  make sim-128              ASCON-128 functional test (shared core)"
	@echo ""
	@echo "Synthesis:"
	@echo "  make synth [ASCON_VARIANT=0|1] [ROUNDS_PER_CYCLE=1|8]"
	@echo "  make synth-all            all four configurations"
	@echo ""
	@echo "GDSII (requires: nix develop + make tt12-python-venv):"
	@echo "  make harden-128a-minarea  ASCON-128a, 6×2 tiles, 10 MHz"
	@echo "  make harden-128a-maxperf  ASCON-128a, 8×2 tiles, 50 MHz"
	@echo "  make harden-128-minarea   ASCON-128,  4×2 tiles, 10 MHz"
	@echo "  make harden-128-maxperf   ASCON-128,  6×2 tiles, 50 MHz"
	@echo ""

$(BUILD):
	mkdir -p $(BUILD)

$(SIM_GEN):
	mkdir -p $(SIM_GEN)

# ── Vector generation ─────────────────────────────────────────────────────
$(SIM_GEN)/ascon_aead128_ad_vectors.vh: tools/gen_vectors.py | $(SIM_GEN)
	python3 tools/gen_vectors.py --variant $(if $(filter 0,$(ASCON_VARIANT)),128,128a) $@

gen-vectors-128a: | $(SIM_GEN)
	python3 tools/gen_vectors.py --variant 128a $(SIM_GEN)/ascon_aead128_ad_vectors.vh

gen-vectors-128: | $(SIM_GEN)
	python3 tools/gen_vectors.py --variant 128 $(SIM_GEN)/ascon_aead128_ad_vectors.vh

# ── Simulation ────────────────────────────────────────────────────────────
$(BUILD)/sim_128a.vvp: $(ALL_SRC) $(TEST)/tb_tt_aead_vectors.v \
    $(SIM_GEN)/ascon_aead128_ad_vectors.vh | $(BUILD)
	$(IVERILOG) -g2005-sv \
	  -I$(SRC) -I$(SRC)/ascon_core -I$(SIM_GEN) \
	  -DASCON_VARIANT_VAL=1 \
	  -P$(TOP).ASCON_VARIANT=1 \
	  -P$(TOP).ROUNDS_PER_CYCLE=1 \
	  -P$(TOP).USE_SHARED_AEAD=1 \
	  -P$(TOP).ENABLE_PERM_DEBUG=0 \
	  -P$(TOP).ENABLE_DIAGNOSTICS=0 \
	  -P$(TOP).ENABLE_OUT_BUFFER=0 \
	  -P$(TOP).MAX_AD_BYTES=32 \
	  -P$(TOP).MAX_DATA_BYTES=32 \
	  -o $@ $(TEST)/tb_tt_aead_vectors.v $(ALL_SRC)

$(BUILD)/sim_128.vvp: $(ALL_SRC) $(TEST)/tb_tt_aead_vectors.v \
    $(SIM_GEN)/ascon_aead128_ad_vectors.vh | $(BUILD)
	$(IVERILOG) -g2005-sv \
	  -I$(SRC) -I$(SRC)/ascon_core -I$(SIM_GEN) \
	  -DASCON_VARIANT_VAL=0 \
	  -P$(TOP).ASCON_VARIANT=0 \
	  -P$(TOP).ROUNDS_PER_CYCLE=1 \
	  -P$(TOP).USE_SHARED_AEAD=1 \
	  -P$(TOP).ENABLE_PERM_DEBUG=0 \
	  -P$(TOP).ENABLE_DIAGNOSTICS=0 \
	  -P$(TOP).ENABLE_OUT_BUFFER=0 \
	  -P$(TOP).MAX_AD_BYTES=32 \
	  -P$(TOP).MAX_DATA_BYTES=32 \
	  -o $@ $(TEST)/tb_tt_aead_vectors.v $(ALL_SRC)

sim-128a: gen-vectors-128a $(BUILD)/sim_128a.vvp
	$(VVP) $(BUILD)/sim_128a.vvp

sim-128: gen-vectors-128 $(BUILD)/sim_128.vvp
	$(VVP) $(BUILD)/sim_128.vvp

# ── Synthesis ─────────────────────────────────────────────────────────────
synth: $(ALL_SRC) | $(BUILD)
	$(YOSYS) -p " \
	  read_verilog $(ALL_SRC); \
	  chparam -set ASCON_VARIANT $(ASCON_VARIANT) \
	          -set ROUNDS_PER_CYCLE $(ROUNDS_PER_CYCLE) \
	          -set USE_SHARED_AEAD $(USE_SHARED_AEAD) $(TOP); \
	  synth -top $(TOP); \
	  stat" | tee $(BUILD)/synth_V$(ASCON_VARIANT)_R$(ROUNDS_PER_CYCLE).log

synth-all:
	$(MAKE) synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1
	$(MAKE) synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=8
	$(MAKE) synth ASCON_VARIANT=0 ROUNDS_PER_CYCLE=1
	$(MAKE) synth ASCON_VARIANT=0 ROUNDS_PER_CYCLE=8

# ── Profile matrix ────────────────────────────────────────────────────────
tt5-profiles: $(ALL_SRC) | $(BUILD)
	@mkdir -p $(BUILD)/tt5
	@for V in 0 1; do for R in 1 8; do \
	  echo "--- ASCON_VARIANT=$$V ROUNDS_PER_CYCLE=$$R ---"; \
	  $(YOSYS) -q -p " \
	    read_verilog $(ALL_SRC); \
	    chparam -set ASCON_VARIANT $$V -set ROUNDS_PER_CYCLE $$R $(TOP); \
	    synth -top $(TOP); stat" \
	    > $(BUILD)/tt5/v$${V}_r$${R}.txt 2>&1; \
	done; done
	python3 tools/report_tt5_profiles.py $(BUILD)/tt5/*.txt || true

# ── Python venv (for hardening) ───────────────────────────────────────────
tt12-python-venv:
	@test -f $(TT_DIR)/requirements.txt || \
	  { echo "ERROR: $(TT_DIR)/requirements.txt not found. Run: git submodule update --init $(TT_DIR)"; exit 1; }
	python3 -m venv $(VENV)
	$(VENV)/bin/pip install --upgrade pip setuptools wheel
	$(VENV)/bin/pip install -r $(TT_DIR)/requirements.txt
	$(VENV)/bin/pip install "librelane==$(LIBRELANE_TAG)"

tt12-python-check:
	@test -x $(PY) || { echo "ERROR: run 'make tt12-python-venv' first"; exit 1; }
	$(PY) -c "import chevron, yaml, git, librelane; print('Python env OK')"
	$(TT_ENV) command -v yowasp-yosys
	$(TT_ENV) $(PY) ./$(TT_DIR)/tt_tool.py --help >/dev/null 2>&1

tt12-python-reset:
	rm -rf $(VENV)

tt12-create-user-config: tt12-python-check
	$(TT_ENV) $(PY) ./$(TT_DIR)/tt_tool.py --create-user-config

tt12-harden:
	$(TT_ENV) $(PY) ./$(TT_DIR)/tt_tool.py --harden

tt12-print-warnings:
	$(TT_ENV) $(PY) ./$(TT_DIR)/tt_tool.py --print-warnings || true

tt12-print-stats:
	$(TT_ENV) $(PY) ./$(TT_DIR)/tt_tool.py --print-stats || true

tt12-create-png:
	$(TT_ENV) $(PY) ./$(TT_DIR)/tt_tool.py --create-png || true

# ── set_tt_config helper ──────────────────────────────────────────────────
# Updates src/config.json + info.yaml for a given tile/clock combination,
# then runs create-user-config and harden.
_harden:
	python3 tools/tt15_set_tt_config.py \
	  --tiles $(TILES) \
	  --clock-hz $(CLOCK_HZ) \
	  --variant $(ASCON_VARIANT) \
	  --rpc $(ROUNDS_PER_CYCLE)
	$(MAKE) tt12-create-user-config
	$(MAKE) tt12-harden

# ── Four GDSII targets ────────────────────────────────────────────────────
harden-128a-minarea:
	$(MAKE) _harden ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1 TILES=6x2 CLOCK_HZ=10000000

harden-128a-maxperf:
	$(MAKE) _harden ASCON_VARIANT=1 ROUNDS_PER_CYCLE=8 TILES=8x2 CLOCK_HZ=50000000

harden-128-minarea:
	$(MAKE) _harden ASCON_VARIANT=0 ROUNDS_PER_CYCLE=1 TILES=4x2 CLOCK_HZ=10000000

harden-128-maxperf:
	$(MAKE) _harden ASCON_VARIANT=0 ROUNDS_PER_CYCLE=8 TILES=6x2 CLOCK_HZ=50000000

# ── Clean ─────────────────────────────────────────────────────────────────
clean:
	rm -rf $(BUILD) $(SIM_GEN)
