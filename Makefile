TOP := tt_um_ascon_aead
SRC_DIR := src
TEST_DIR := test
BUILD_DIR := build

ASCON_RTL ?= ../ascon-rtl
ASCON_RTL_WORKTREE ?= ../ascon-rtl
SIM_GEN_DIR ?= sim/generated
ASCON_CORE_RTL_DIR ?= $(SRC_DIR)/ascon_core
ASCON_RTL_RTL ?= $(ASCON_CORE_RTL_DIR)
ASCON_RTL_VEC_AD := $(SIM_GEN_DIR)/ascon_aead128_ad_vectors.vh

IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
YOSYS ?= yosys
TT_TOOLS_DIR ?= tt
PDK_ROOT ?= $(CURDIR)/.ttsetup/pdk
PDK ?= sky130A
LIBRELANE_TAG ?= 3.0.0rc1


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
	$(SRC_DIR)/ascon_tt_aead_bridge.v

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

sim: $(BUILD_DIR)/tb_tt_um_ascon_aead.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_um_ascon_aead.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_um_ascon_aead.v | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(SIM_GEN_DIR) $(TT_DEBUG_PARAMS) -o $@ $(TEST_DIR)/tb_tt_um_ascon_aead.v $(SRC_FILES)

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
	mkdir -p $(SIM_GEN_DIR)
	@if [ ! -d "$(ASCON_RTL_WORKTREE)" ]; then \
		echo "ERROR: ASCON_RTL_WORKTREE=$(ASCON_RTL_WORKTREE) does not exist."; \
		echo "Use a writable ascon-rtl checkout for vector generation, not the read-only Nix store ASCON_RTL."; \
		exit 1; \
	fi
	$(MAKE) -C $(ASCON_RTL_WORKTREE) vectors-ascon-c
	cp $(ASCON_RTL_WORKTREE)/sim/generated/ascon_aead128_ad_vectors.vh $(ASCON_RTL_VEC_AD)

sim-aead-vectors: $(BUILD_DIR)/tb_tt_aead_vectors.vvp
	$(VVP) $<

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
	rm -rf $(TT5_DIR)

tt5-full-debug: $(TT5_DIR)/full_debug.txt
tt5-full-aead-bridge: $(TT5_DIR)/full_aead_bridge.txt
tt5-enc-only: $(TT5_DIR)/enc_only.txt
tt5-dec-only: $(TT5_DIR)/dec_only.txt
tt5-perm-debug: $(TT5_DIR)/perm_debug.txt
tt5-perm-core: $(TT5_DIR)/perm_core.txt

tt5-profiles: tt5-full-debug tt5-full-aead-bridge tt5-enc-only tt5-dec-only tt5-perm-debug tt5-perm-core $(TT5_DIR)/full_aead_top.txt $(TT5_DIR)/prod_aead_top.txt
	$(MAKE) tt5-report

tt5-report:
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

tt12-harden: tt11b-tools-check
	$(TT_ENV) $(TT_ENV) $(PY_TT) ./$(TT_TOOLS_DIR)/tt_tool.py --harden

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
TT_ENV ?= PATH=$(CURDIR)/$(PY_VENV)/bin:$(PATH) PDK_ROOT=$(PDK_ROOT) PDK=$(PDK) LIBRELANE_TAG=$(LIBRELANE_TAG)

tt12-python-reset:
	rm -rf $(PY_VENV)

tt12-python-venv:
	test -f tt/requirements.txt
	$(PYTHON) -m venv $(PY_VENV)
	$(PY_TT) -m pip install --upgrade pip setuptools wheel
	$(PY_TT) -m pip install -r tt/requirements.txt
	$(PY_TT) -m pip install yowasp-yosys
	$(PY_TT) -m pip install "librelane==$(LIBRELANE_TAG)"
	$(PY_TT) -c "import chevron, yaml, git; print('tt python deps OK')"

tt12-python-check:
	test -x $(PY_TT)
	$(PY_TT) -c "import chevron, yaml, git; import klayout.db as pya; import cairosvg; import librelane; print('tt python deps + klayout + cairosvg + librelane OK')"
	$(TT_ENV) command -v yowasp-yosys
	$(TT_ENV) $(PY_TT) ./tt/tt_tool.py --help >/dev/null

tt12-python-freeze:
	test -x $(PY_VENV)/bin/python
	$(PY_TT) -m pip freeze | sort > build/tt12_python_freeze.txt
	cat build/tt12_python_freeze.txt

# ---------------------------------------------------------------------------
# TT-12F HARDENING ENTRYPOINT
# ---------------------------------------------------------------------------

.PHONY: tt12-pre-harden-check

tt12-pre-harden-check:
	$(MAKE) tt12-env-check
	$(MAKE) tt12-librelane-check
	$(MAKE) sanity
	$(MAKE) tt10-flow-preflight
	$(MAKE) tt11b-tools-check
	$(MAKE) tt12-python-check
	$(MAKE) lint
	$(MAKE) synth


.PHONY: tt12h-check-config

tt12h-check-config:
	$(PY_TT) tools/tt12h_check_config.py

.PHONY: tt12-librelane-install tt12-librelane-check tt12-env-check

tt12-librelane-install:
	test -x $(PY_TT)
	$(PY_TT) -m pip install "librelane==$(LIBRELANE_TAG)"

tt12-librelane-check:
	test -x $(PY_TT)
	$(PY_TT) -c "import librelane; print('librelane import OK')"
	$(TT_ENV) $(PY_TT) -m librelane --version || true

tt12-env-check:
	@echo "PDK_ROOT=$(PDK_ROOT)"
	@echo "PDK=$(PDK)"
	@echo "LIBRELANE_TAG=$(LIBRELANE_TAG)"
	@test -n "$(PDK_ROOT)"
	@test -n "$(PDK)"
	@test -n "$(LIBRELANE_TAG)"
	@mkdir -p "$(PDK_ROOT)"


# ---------------------------------------------------------------------------
# TT-13 AREA FIT TRIAGE
# ---------------------------------------------------------------------------

.PHONY: tt13-area-report

tt13-area-report:
	python3 tools/tt13_area_fit_report.py runs build | tee build/tt13/area_fit_report.md
