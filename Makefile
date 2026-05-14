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
TOP := tt_um_ascon_aead
SRC_DIR := src
TEST_DIR := test
BUILD_DIR := build

ASCON_RTL ?= ../ascon-rtl
ASCON_RTL_WORKTREE ?= ../ascon-rtl
ASCON_C_DIR ?= $(ASCON_RTL)/../ascon-c
CC ?= gcc
SIM_GEN_DIR ?= sim/generated
ASCON_CORE_RTL_DIR ?= $(SRC_DIR)/ascon_core
ASCON_RTL_RTL ?= $(ASCON_CORE_RTL_DIR)
ASCON_RTL_VEC_AD := $(SIM_GEN_DIR)/ascon_aead128_ad_vectors.vh

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
TT_DEBUG_PARAMS := \
	-DTT_DEBUG_DEFAULTS \
	-P $(TOP).ENABLE_PERM_DEBUG=1 \
	-P $(TOP).ENABLE_DIAGNOSTICS=1 \
	-P $(TOP).ENABLE_OUT_BUFFER=1 \
	-P $(TOP).MAX_AD_BYTES=32 \
	-P $(TOP).MAX_DATA_BYTES=32

TT_PROD_PARAMS := \
	-P $(TOP).ENABLE_PERM_DEBUG=0 \
	-P $(TOP).ENABLE_DIAGNOSTICS=0 \
	-P $(TOP).ENABLE_OUT_BUFFER=0 \
	-P $(TOP).MAX_AD_BYTES=32 \
	-P $(TOP).MAX_DATA_BYTES=32


LOCAL_SRC_FILES := \
	$(SRC_DIR)/project.v \
	$(SRC_DIR)/ascon_tt_serial_frontend.v \
	$(SRC_DIR)/ascon_tt_aead_core_stub.v \
	$(SRC_DIR)/ascon_tt_perm_core.v \
	$(SRC_DIR)/ascon_tt_aead_shared.v

ASCON_RTL_FILES := \
	$(ASCON_RTL_RTL)/ascon_round_comb.v \
	$(ASCON_RTL_RTL)/ascon_perm_unrolled.v \
	$(ASCON_RTL_RTL)/ascon_aead128_enc_ad.v \
	$(ASCON_RTL_RTL)/ascon_aead128_dec_ad.v

SRC_FILES := $(LOCAL_SRC_FILES) $(ASCON_RTL_FILES)

.PHONY: all clean sim lint synth sanity

all: sim lint synth

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

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
	$(VERILATOR) --lint-only --timing -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -I$(SRC_DIR) -I$(ASCON_RTL_RTL) --top-module $(TOP) $(SRC_FILES)

synth: | $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); synth -top $(TOP); check; stat' > $(BUILD_DIR)/yosys_tt_scaffold_stat.txt
	cat $(BUILD_DIR)/yosys_tt_scaffold_stat.txt

sanity:
	@test -f .gitignore || { echo "ERROR: missing .gitignore"; exit 1; }
	@test -f info.yaml
	@test -f src/project.v
	@test -f src/config.json
	@test -f src/ascon_tt_perm_core.v
	@test -f docs/info.md
	@test -f docs/architecture.md
	@test -f src/ascon_core/ascon_round_comb.v
	@test -f src/ascon_core/ascon_perm_unrolled.v
	@bad="$$(find . \
		-path ./.git -prune -o \
		-path ./.ttsetup -prune -o \
		-path ./build -prune -o \
		-path ./.venv -prune -o \
		-path ./tt -prune -o \
		-path ./runs -prune -o \
		-path ./artifacts/runs -prune -o \
		-path ./sim/generated -prune -o \
		\( -name '*.rej' -o -name '*.orig' -o -name '*.patch' -o -name '*.zip' -o -name '*.tar.gz' \) -print)"; \
	if [ -n "$$bad" ]; then \
		echo "ERROR: stale/generated artifact files found:"; \
		echo "$$bad"; \
		exit 1; \
	fi
	@echo "sanity OK"

clean:
	rm -rf $(BUILD_DIR)
	rm -f *.vvp *.vcd *.fst

# ---------------------------------------------------------------------------
# TT-3.1 PERMUTATION ORACLE TEST
# ---------------------------------------------------------------------------

.PHONY: sim-perm-oracle

sim-perm-oracle: $(BUILD_DIR)/tb_tt_perm_oracle.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_perm_oracle.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_perm_oracle.v | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(SIM_GEN_DIR) $(TT_DEBUG_PARAMS) -o $@ $(TEST_DIR)/tb_tt_perm_oracle.v $(SRC_FILES)

# ---------------------------------------------------------------------------
# TT-4A JOB BUFFER TEST
# ---------------------------------------------------------------------------

.PHONY: sim-job-buffers

sim-job-buffers: $(BUILD_DIR)/tb_tt_job_buffers.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_job_buffers.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_job_buffers.v | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(SIM_GEN_DIR) $(TT_DEBUG_PARAMS) -o $@ $(TEST_DIR)/tb_tt_job_buffers.v $(SRC_FILES)

# ---------------------------------------------------------------------------
# TT-4B FULL AEAD VECTOR TEST
# ---------------------------------------------------------------------------

.PHONY: sim-aead-vectors

$(ASCON_RTL_VEC_AD):
	mkdir -p $(SIM_GEN_DIR) $(BUILD_DIR)
	@test -n "$(ASCON_RTL)"   || { echo "ERROR: ASCON_RTL not set. Run inside: nix develop"; exit 1; }
	@test -d "$(ASCON_RTL)"   || { echo "ERROR: ASCON_RTL=$(ASCON_RTL) does not exist"; exit 1; }
	@test -n "$(ASCON_C_DIR)" || { echo "ERROR: ASCON_C_DIR not set. Run inside: nix develop"; exit 1; }
	@test -d "$(ASCON_C_DIR)" || { echo "ERROR: ASCON_C_DIR=$(ASCON_C_DIR) does not exist"; exit 1; }
	$(CC) -std=c99 -O2 \
		-I$(ASCON_C_DIR)/src \
		-I$(ASCON_C_DIR)/src/opt64 \
		-I$(ASCON_C_DIR)/crypto_aead/asconaead128/ref \
		$(ASCON_RTL)/tools/ascon_c_aead128_ad_vectors.c \
		-o $(BUILD_DIR)/ascon_c_aead128_ad_vectors
	$(BUILD_DIR)/ascon_c_aead128_ad_vectors > $(ASCON_RTL_VEC_AD)

sim-aead-vectors: $(BUILD_DIR)/tb_tt_aead_vectors.vvp
	$(VVP) $<

.PHONY: gen-vectors
gen-vectors:
	rm -f $(ASCON_RTL_VEC_AD)
	$(MAKE) $(ASCON_RTL_VEC_AD)

$(BUILD_DIR)/tb_tt_aead_vectors.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_aead_vectors.v $(ASCON_RTL_VEC_AD) | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(SIM_GEN_DIR) -o $@ $(TEST_DIR)/tb_tt_aead_vectors.v $(SRC_FILES)

# ---------------------------------------------------------------------------
# TT-5 PROFILE MATRIX
# ---------------------------------------------------------------------------

TT5_DIR := $(BUILD_DIR)/tt5

.PHONY: tt5-profiles tt5-report tt5-clean tt5-full-debug tt5-full-aead-bridge tt5-enc-only tt5-dec-only tt5-perm-debug tt5-perm-core

$(TT5_DIR):
	mkdir -p $(TT5_DIR)

tt5-clean:
	rm -rf $(BUILD)/tt5

tt5-profiles: $(ALL_SRC) | $(BUILD)/tt5
	python3 tools/tt5_run_profiles.py --out-dir $(BUILD)/tt5
	python3 tools/report_tt5_profiles.py $(BUILD)/tt5/v*.txt

tt5-report:
	python3 tools/report_tt5_profiles.py $(BUILD)/tt5/v*.txt
	python3 tools/report_tt5_profiles.py $(TT5_DIR)/*.txt

$(TT5_DIR)/full_debug.txt: $(SRC_FILES) | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); synth -top $(TOP); check; stat' > $@

$(TT5_DIR)/full_aead_bridge.txt: $(SRC_DIR)/ascon_tt_aead_bridge.v $(ASCON_RTL_FILES) | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_DIR)/ascon_tt_aead_bridge.v $(ASCON_RTL_FILES); synth -top ascon_tt_aead_bridge; check; stat' > $@

$(TT5_DIR)/enc_only.txt: $(ASCON_RTL_FILES) | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(ASCON_RTL_FILES); synth -top ascon_aead128_enc_ad; check; stat' > $@

$(TT5_DIR)/dec_only.txt: $(ASCON_RTL_FILES) | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(ASCON_RTL_FILES); synth -top ascon_aead128_dec_ad; check; stat' > $@

$(TT5_DIR)/perm_debug.txt: $(SRC_DIR)/ascon_tt_perm_core.v $(ASCON_RTL_RTL)/ascon_round_comb.v $(ASCON_RTL_RTL)/ascon_perm_unrolled.v | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_DIR)/ascon_tt_perm_core.v $(ASCON_RTL_RTL)/ascon_round_comb.v $(ASCON_RTL_RTL)/ascon_perm_unrolled.v; synth -top ascon_tt_perm_core; check; stat' > $@

$(TT5_DIR)/perm_core.txt: $(ASCON_RTL_RTL)/ascon_round_comb.v $(ASCON_RTL_RTL)/ascon_perm_unrolled.v | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(ASCON_RTL_RTL)/ascon_round_comb.v $(ASCON_RTL_RTL)/ascon_perm_unrolled.v; synth -top ascon_perm_unrolled; check; stat' > $@


# ---------------------------------------------------------------------------
# TT-6 NO-PERM FULL-AEAD TOP PROFILE
# ---------------------------------------------------------------------------

.PHONY: sim-aead-vectors-noperm synth-full-aead-top tt6-report

sim-aead-vectors-noperm: $(BUILD_DIR)/tb_tt_aead_vectors_noperm.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_aead_vectors_noperm.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_aead_vectors.v $(ASCON_RTL_VEC_AD) | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(SIM_GEN_DIR) \
		-P $(TOP).ENABLE_PERM_DEBUG=0 \
		-o $@ $(TEST_DIR)/tb_tt_aead_vectors.v $(SRC_FILES)

synth-full-aead-top: | $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); synth -top $(TOP); check; stat' > $(BUILD_DIR)/yosys_tt_full_aead_top_stat.txt
	cat $(BUILD_DIR)/yosys_tt_full_aead_top_stat.txt

$(TT5_DIR)/full_aead_top.txt: $(SRC_FILES) | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); synth -top $(TOP); check; stat' > $@

tt6-report: $(TT5_DIR)/full_debug.txt $(TT5_DIR)/full_aead_top.txt $(TT5_DIR)/full_aead_bridge.txt $(TT5_DIR)/perm_debug.txt $(TT5_DIR)/perm_core.txt
	python3 tools/report_tt5_profiles.py $^


# ---------------------------------------------------------------------------
# TT-7A SLIM NO-PERM FRONTEND CHECKS
# ---------------------------------------------------------------------------

.PHONY: tt7a-check tt7a-report

tt7a-check:
	$(MAKE) sim-aead-vectors-noperm
	$(MAKE) synth-full-aead-top
	$(MAKE) tt6-report

tt7a-report: tt6-report


# ---------------------------------------------------------------------------
# TT-7A.2 PRODUCTION DIAGNOSTICS-OFF PROFILE
# ---------------------------------------------------------------------------

.PHONY: sim-aead-vectors-prod synth-prod-aead-top tt7a2-report tt7a2-check

sim-aead-vectors-prod: $(BUILD_DIR)/tb_tt_aead_vectors_prod.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_aead_vectors_prod.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_aead_vectors.v $(ASCON_RTL_VEC_AD) | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(SIM_GEN_DIR) \
		-P $(TOP).ENABLE_PERM_DEBUG=0 \
		-P $(TOP).ENABLE_DIAGNOSTICS=0 \
		-o $@ $(TEST_DIR)/tb_tt_aead_vectors.v $(SRC_FILES)

synth-prod-aead-top: | $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); synth -top $(TOP); check; stat' > $(BUILD_DIR)/yosys_tt_prod_aead_top_stat.txt
	cat $(BUILD_DIR)/yosys_tt_prod_aead_top_stat.txt

$(TT5_DIR)/prod_aead_top.txt: $(SRC_FILES) | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); synth -top $(TOP); check; stat' > $@

tt7a2-report: $(TT5_DIR)/full_debug.txt $(TT5_DIR)/full_aead_top.txt $(TT5_DIR)/prod_aead_top.txt $(TT5_DIR)/full_aead_bridge.txt $(TT5_DIR)/perm_debug.txt $(TT5_DIR)/perm_core.txt
	python3 tools/report_tt5_profiles.py $^

tt7a2-check:
	$(MAKE) sim-aead-vectors-prod
	$(MAKE) synth-prod-aead-top
	$(MAKE) tt7a2-report


# ---------------------------------------------------------------------------
# TT-7A.3 PRODUCTION BUFFER-SIZE MATRIX
# ---------------------------------------------------------------------------

TT7A3_DIR := $(BUILD_DIR)/tt7a3

.PHONY: tt7a3-buffer-matrix tt7a3-report tt7a3-clean

$(TT7A3_DIR):
	mkdir -p $(TT7A3_DIR)

tt7a3-clean:
	rm -rf $(TT7A3_DIR)

tt7a3-buffer-matrix: \
	$(TT7A3_DIR)/prod_aead_top_ad8_msg8.txt \
	$(TT7A3_DIR)/prod_aead_top_ad16_msg16.txt \
	$(TT7A3_DIR)/prod_aead_top_ad32_msg32.txt \
	$(TT7A3_DIR)/prod_aead_top_ad8_msg32.txt \
	$(TT7A3_DIR)/prod_aead_top_ad32_msg8.txt
	$(MAKE) tt7a3-report

tt7a3-report:
	python3 tools/report_tt5_profiles.py $(TT7A3_DIR)/*.txt

$(TT7A3_DIR)/prod_aead_top_ad8_msg8.txt: $(SRC_FILES) | $(TT7A3_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set MAX_AD_BYTES 8 $(TOP); chparam -set MAX_DATA_BYTES 8 $(TOP); synth -top $(TOP); check; stat' > $@

$(TT7A3_DIR)/prod_aead_top_ad16_msg16.txt: $(SRC_FILES) | $(TT7A3_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set MAX_AD_BYTES 16 $(TOP); chparam -set MAX_DATA_BYTES 16 $(TOP); synth -top $(TOP); check; stat' > $@

$(TT7A3_DIR)/prod_aead_top_ad32_msg32.txt: $(SRC_FILES) | $(TT7A3_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set MAX_AD_BYTES 32 $(TOP); chparam -set MAX_DATA_BYTES 32 $(TOP); synth -top $(TOP); check; stat' > $@

$(TT7A3_DIR)/prod_aead_top_ad8_msg32.txt: $(SRC_FILES) | $(TT7A3_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set MAX_AD_BYTES 8 $(TOP); chparam -set MAX_DATA_BYTES 32 $(TOP); synth -top $(TOP); check; stat' > $@

$(TT7A3_DIR)/prod_aead_top_ad32_msg8.txt: $(SRC_FILES) | $(TT7A3_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set MAX_AD_BYTES 32 $(TOP); chparam -set MAX_DATA_BYTES 8 $(TOP); synth -top $(TOP); check; stat' > $@


# ---------------------------------------------------------------------------
# TT-7A.4 DIRECT-OUTPUT PRODUCTION PROFILE
# ---------------------------------------------------------------------------

.PHONY: sim-aead-vectors-prod-directout synth-prod-aead-top-directout tt7a4-report tt7a4-check

sim-aead-vectors-prod-directout: $(BUILD_DIR)/tb_tt_aead_vectors_prod_directout.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_aead_vectors_prod_directout.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_aead_vectors.v $(ASCON_RTL_VEC_AD) | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(SIM_GEN_DIR) \
		-P $(TOP).ENABLE_PERM_DEBUG=0 \
		-P $(TOP).ENABLE_DIAGNOSTICS=0 \
		-P $(TOP).ENABLE_OUT_BUFFER=0 \
		-P $(TOP).MAX_AD_BYTES=32 \
		-P $(TOP).MAX_DATA_BYTES=32 \
		-o $@ $(TEST_DIR)/tb_tt_aead_vectors.v $(SRC_FILES)

synth-prod-aead-top-directout: | $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set ENABLE_OUT_BUFFER 0 $(TOP); synth -top $(TOP); check; stat' > $(BUILD_DIR)/yosys_tt_prod_aead_top_directout_stat.txt
	cat $(BUILD_DIR)/yosys_tt_prod_aead_top_directout_stat.txt

$(TT5_DIR)/prod_aead_top_directout.txt: $(SRC_FILES) | $(TT5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set ENABLE_OUT_BUFFER 0 $(TOP); synth -top $(TOP); check; stat' > $@

tt7a4-report: $(TT5_DIR)/full_aead_bridge.txt $(TT5_DIR)/prod_aead_top.txt $(TT5_DIR)/prod_aead_top_directout.txt $(TT5_DIR)/perm_core.txt
	python3 tools/report_tt5_profiles.py $^

tt7a4-check:
	$(MAKE) sim-aead-vectors-prod-directout
	$(MAKE) synth-prod-aead-top-directout
	$(MAKE) tt7a4-report


# ---------------------------------------------------------------------------
# TT-7A.5 DIRECT-OUTPUT BUFFER-SIZE MATRIX
# ---------------------------------------------------------------------------

TT7A5_DIR := $(BUILD_DIR)/tt7a5

.PHONY: tt7a5-directout-buffer-matrix tt7a5-report tt7a5-clean

$(TT7A5_DIR):
	mkdir -p $(TT7A5_DIR)

tt7a5-clean:
	rm -rf $(TT7A5_DIR)

tt7a5-directout-buffer-matrix: \
	$(TT7A5_DIR)/prod_directout_ad8_msg8.txt \
	$(TT7A5_DIR)/prod_directout_ad16_msg16.txt \
	$(TT7A5_DIR)/prod_directout_ad32_msg32.txt \
	$(TT7A5_DIR)/prod_directout_ad8_msg32.txt \
	$(TT7A5_DIR)/prod_directout_ad32_msg8.txt
	$(MAKE) tt7a5-report

tt7a5-report:
	python3 tools/report_tt5_profiles.py $(TT7A5_DIR)/*.txt

$(TT7A5_DIR)/prod_directout_ad8_msg8.txt: $(SRC_FILES) | $(TT7A5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set ENABLE_OUT_BUFFER 0 $(TOP); chparam -set MAX_AD_BYTES 8 $(TOP); chparam -set MAX_DATA_BYTES 8 $(TOP); synth -top $(TOP); check; stat' > $@

$(TT7A5_DIR)/prod_directout_ad16_msg16.txt: $(SRC_FILES) | $(TT7A5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set ENABLE_OUT_BUFFER 0 $(TOP); chparam -set MAX_AD_BYTES 16 $(TOP); chparam -set MAX_DATA_BYTES 16 $(TOP); synth -top $(TOP); check; stat' > $@

$(TT7A5_DIR)/prod_directout_ad32_msg32.txt: $(SRC_FILES) | $(TT7A5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set ENABLE_OUT_BUFFER 0 $(TOP); chparam -set MAX_AD_BYTES 32 $(TOP); chparam -set MAX_DATA_BYTES 32 $(TOP); synth -top $(TOP); check; stat' > $@

$(TT7A5_DIR)/prod_directout_ad8_msg32.txt: $(SRC_FILES) | $(TT7A5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set ENABLE_OUT_BUFFER 0 $(TOP); chparam -set MAX_AD_BYTES 8 $(TOP); chparam -set MAX_DATA_BYTES 32 $(TOP); synth -top $(TOP); check; stat' > $@

$(TT7A5_DIR)/prod_directout_ad32_msg8.txt: $(SRC_FILES) | $(TT7A5_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); chparam -set ENABLE_PERM_DEBUG 0 $(TOP); chparam -set ENABLE_DIAGNOSTICS 0 $(TOP); chparam -set ENABLE_OUT_BUFFER 0 $(TOP); chparam -set MAX_AD_BYTES 32 $(TOP); chparam -set MAX_DATA_BYTES 8 $(TOP); synth -top $(TOP); check; stat' > $@


# ---------------------------------------------------------------------------
# TT-8 PRODUCTION-DEFAULT CHECKS
# ---------------------------------------------------------------------------

.PHONY: prod-default-check debug-regression prod-default-report

prod-default-check:
	$(MAKE) sanity
	$(MAKE) sim-aead-vectors-prod-directout
	$(MAKE) synth

debug-regression:
	$(MAKE) sim
	$(MAKE) sim-perm-oracle
	$(MAKE) sim-job-buffers

prod-default-report:
	python3 tools/report_tt5_profiles.py $(BUILD_DIR)/yosys_tt_scaffold_stat.txt


# ---------------------------------------------------------------------------
# TT-9 REPO HARDENING / RELEASE CHECKS
# ---------------------------------------------------------------------------

.PHONY: tt9-audit tt9-area-summary tt9-release-check

tt9-audit:
	python3 tools/tt9_audit.py

tt9-area-summary:
	python3 tools/tt9_area_summary.py $(BUILD_DIR)/yosys_tt_scaffold_stat.txt

tt9-release-check:
	$(MAKE) clean
	$(MAKE) sanity
	$(MAKE) debug-regression
	$(MAKE) sim-aead-vectors-prod-directout
	$(MAKE) lint
	$(MAKE) synth
	$(MAKE) prod-default-report
	$(MAKE) tt9-audit


# ---------------------------------------------------------------------------
# TT-10 PHYSICAL-FLOW PREFLIGHT
# ---------------------------------------------------------------------------

.PHONY: tt10-flow-preflight tt10-release-check tt10-area-summary

tt10-flow-preflight:
	$(PY_TT) tools/tt10_flow_preflight.py

tt10-area-summary:
	python3 tools/tt9_area_summary.py $(BUILD_DIR)/yosys_tt_scaffold_stat.txt

tt10-release-check:
	$(MAKE) tt9-release-check
	$(MAKE) tt10-flow-preflight


# ---------------------------------------------------------------------------
# TT-10B PACKAGED CORE RTL
# ---------------------------------------------------------------------------

.PHONY: tt10b-refresh-core tt10b-package-check

tt10b-refresh-core:
	test -d "$(ASCON_RTL)/rtl"
	mkdir -p $(ASCON_CORE_RTL_DIR)
	cp $(ASCON_RTL)/rtl/ascon_round_comb.v $(ASCON_CORE_RTL_DIR)/ascon_round_comb.v
	cp $(ASCON_RTL)/rtl/ascon_perm_unrolled.v $(ASCON_CORE_RTL_DIR)/ascon_perm_unrolled.v
	cp $(ASCON_RTL)/rtl/ascon_aead128_enc_ad.v $(ASCON_CORE_RTL_DIR)/ascon_aead128_enc_ad.v
	cp $(ASCON_RTL)/rtl/ascon_aead128_dec_ad.v $(ASCON_CORE_RTL_DIR)/ascon_aead128_dec_ad.v

tt10b-package-check:
	test -f $(ASCON_CORE_RTL_DIR)/ascon_round_comb.v
	test -f $(ASCON_CORE_RTL_DIR)/ascon_perm_unrolled.v
	test -f $(ASCON_CORE_RTL_DIR)/ascon_aead128_enc_ad.v
	test -f $(ASCON_CORE_RTL_DIR)/ascon_aead128_dec_ad.v
	$(MAKE) tt10-flow-preflight


# ---------------------------------------------------------------------------
# TT-11 HARDENING HANDOFF
# ---------------------------------------------------------------------------

.PHONY: tt11-harden-preflight tt11-snapshot tt11-pre-gds-check

tt11-harden-preflight:
	$(PY_TT) tools/tt11_hardening_preflight.py

tt11-snapshot:
	tools/tt11_make_snapshot.sh

tt11-pre-gds-check:
	$(MAKE) tt10-release-check
	$(MAKE) tt11-harden-preflight


# ---------------------------------------------------------------------------
# TT-11B SUPPORT TOOLS SUBMODULE / TT-12 WRAPPERS
# ---------------------------------------------------------------------------

.PHONY: tt11b-tools-check tt11b-submodule-status \
        tt12-create-user-config tt12-harden tt12-print-warnings \
        tt12-print-stats tt12-print-cell-category tt12-create-submission \
        tt12-create-png tt12-first-hardening-run

tt11b-tools-check:
	test -f $(TT_TOOLS_DIR)/tt_tool.py
	test -f $(TT_TOOLS_DIR)/requirements.txt
	@if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then \
		if git config --file .gitmodules --get-regexp 'submodule\.$(TT_TOOLS_DIR)\.path' >/dev/null 2>&1; then \
			git submodule status --recursive $(TT_TOOLS_DIR); \
		else \
			echo "ERROR: $(TT_TOOLS_DIR)/ exists but is not recorded as a submodule in .gitmodules"; \
			echo "Run fix_tt12_repo_hygiene_and_tools.sh from the real Git repo, or add the submodule manually."; \
			exit 1; \
		fi; \
	else \
		echo "WARN: not a Git repo; checked $(TT_TOOLS_DIR)/ files only"; \
	fi

tt11b-submodule-status:
	git submodule status --recursive

tt12-create-user-config: tt11b-tools-check
	@test -f src/config.json || { echo "ERROR: missing src/config.json"; exit 1; }
	$(TT_ENV) $(TT_ENV) $(PY_TT) ./$(TT_TOOLS_DIR)/tt_tool.py --create-user-config

tt12-harden: sanity lint synth tt11b-tools-check
	@test -f src/user_config.json || { \
		echo "ERROR: src/user_config.json missing. Run: make tt12-create-user-config"; \
		exit 1; \
	}
	@test -n "$(PDK_ROOT)" || { echo "ERROR: PDK_ROOT not set"; exit 1; }
	$(TT_ENV) $(PY_TT) -m librelane \
		--pdk-root $(PDK_ROOT) \
		--pdk $(PDK) \
		--design-dir $(SRC_DIR) \
		$(SRC_DIR)/config.json \
		$(SRC_DIR)/user_config.json

tt12-print-warnings: tt11b-tools-check
	@if [ ! -d runs/wokwi ] && [ ! -d build/tt12b ]; then echo "No completed hardening run found yet."; exit 0; fi
	-$(TT_ENV) $(PY_TT) ./$(TT_TOOLS_DIR)/tt_tool.py --print-warnings
tt12-print-stats: tt11b-tools-check
	@if [ ! -d runs/wokwi ] && [ ! -d build/tt12b ]; then echo "No completed hardening run found yet."; exit 0; fi
	-$(TT_ENV) $(PY_TT) ./$(TT_TOOLS_DIR)/tt_tool.py --print-stats
tt12-print-cell-category: tt11b-tools-check
	@if [ ! -d runs/wokwi ] && [ ! -d build/tt12b ]; then echo "No completed hardening run found yet."; exit 0; fi
	-$(TT_ENV) $(PY_TT) ./$(TT_TOOLS_DIR)/tt_tool.py --print-cell-category
tt12-create-submission: tt11b-tools-check
	$(TT_ENV) $(TT_ENV) $(PY_TT) ./$(TT_TOOLS_DIR)/tt_tool.py --create-tt-submission

tt12-create-png: tt11b-tools-check
	$(TT_ENV) $(TT_ENV) $(PY_TT) ./$(TT_TOOLS_DIR)/tt_tool.py --create-png

tt12-first-hardening-run:
	$(MAKE) tt12-pre-harden-check
	$(MAKE) tt12-create-user-config
	$(MAKE) tt12-harden
	$(MAKE) tt12-print-warnings
	$(MAKE) tt12-print-stats
	$(MAKE) tt12-print-cell-category
# ---------------------------------------------------------------------------
# TT-12A LAYOUT ARTIFACT POLICY
# ---------------------------------------------------------------------------

.PHONY: tt12a-artifact-policy-check tt12a-capture tt12a-manifest tt12a-dvc-status

RUN_NAME ?= harden
RUN_DIR ?= runs/wokwi
ARTIFACT_DIR ?=

tt12a-artifact-policy-check:
	test -x tools/tt12a_capture_hardening_artifact.sh
	test -x tools/tt12a_make_manifest.py
	test -x tools/tt12a_compare_manifests.py
	test -d artifacts/runs
	test -d artifacts/manifests

tt12a-capture:
	tools/tt12a_capture_hardening_artifact.sh "$(RUN_NAME)" "$(RUN_DIR)"

tt12a-manifest:
	test -n "$(ARTIFACT_DIR)"
	python3 tools/tt12a_make_manifest.py "$(ARTIFACT_DIR)"

tt12a-dvc-status:
	@if command -v dvc >/dev/null 2>&1; then \
		dvc status; \
	else \
		echo "DVC not installed. Install/configure DVC only when ready to track generated layout artifacts."; \
	fi


# ---------------------------------------------------------------------------
# TT-12B FIRST HARDENING RUN TRIAGE
# ---------------------------------------------------------------------------

.PHONY: tt12b-find-run-dir tt12b-triage tt12b-after-harden tt12b-first-hardening-run

tt12b-find-run-dir:
	python3 tools/tt12b_find_run_dir.py runs build

tt12b-triage:
	test -n "$(RUN_DIR)"
	python3 tools/tt12b_triage_reports.py "$(RUN_DIR)" build/tt12b/triage.md

tt12b-after-harden:
	tools/tt12b_after_harden.sh

tt12b-first-hardening-run:
	$(MAKE) tt12-pre-harden-check
	$(MAKE) tt12-create-user-config
	$(MAKE) tt12-harden
	$(MAKE) tt12b-after-harden
# ---------------------------------------------------------------------------
# TT-12 PYTHON ENVIRONMENT
# ---------------------------------------------------------------------------

.PHONY: tt12-python-reset tt12-python-venv tt12-python-check tt12-python-freeze

PY_VENV ?= .venv
PYTHON ?= python3
PY_TT ?= $(PY_VENV)/bin/python
VENV_SITE = $(shell $(PY_TT) -c "import site; print(site.getsitepackages()[0])" 2>/dev/null)
TT_ENV ?= PATH=$(CURDIR)/$(PY_VENV)/bin:$(PATH) \
          PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) LIBRELANE_TAG=$(LIBRELANE_TAG) \
          PYTHONPATH=$(VENV_SITE)

tt12-python-reset:
	rm -rf $(PY_VENV)

# ── Python venv ────────────────────────────────────────────────────────────────
tt12-python-venv:
	test -f tt/requirements.txt
	$(PYTHON) -m venv $(PY_VENV)
	$(PY_TT) -m pip install --upgrade pip setuptools wheel
	$(PY_TT) -m pip install --only-binary=numpy "numpy<2.0" || \
		$(PY_TT) -m pip install "numpy<1.27"
	$(PY_TT) -m pip install -r tt/requirements.txt
	$(PY_TT) -m pip install yowasp-yosys
	$(PY_TT) -m pip install "librelane==$(LIBRELANE_TAG)"
	$(PY_TT) -c "import chevron, yaml, git; print('tt python deps OK')"

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
	@echo "== generated dirs =="
	@find build runs sim/generated artifacts/runs -maxdepth 2 2>/dev/null | sort | head -80 || truep
