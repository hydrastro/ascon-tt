TOP := tt_um_ascon_aead
SRC_DIR := src
TEST_DIR := test
BUILD_DIR := build

ASCON_RTL ?= ../ascon-rtl
ASCON_RTL_RTL := $(ASCON_RTL)/rtl
ASCON_RTL_VEC_AD := $(ASCON_RTL)/sim/generated/ascon_aead128_ad_vectors.vh

IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
YOSYS ?= yosys

TT_DEBUG_PARAMS := \
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
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated $(TT_DEBUG_PARAMS) -o $@ $(TEST_DIR)/tb_tt_um_ascon_aead.v $(SRC_FILES)

lint:
	$(VERILATOR) --lint-only --timing -Wall -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -Wno-WIDTHEXPAND -I$(SRC_DIR) -I$(ASCON_RTL_RTL) --top-module $(TOP) $(SRC_FILES)

synth: | $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); synth -top $(TOP); check; stat' > $(BUILD_DIR)/yosys_tt_scaffold_stat.txt
	cat $(BUILD_DIR)/yosys_tt_scaffold_stat.txt

sanity:
	@test -f info.yaml || { echo "ERROR: missing info.yaml"; exit 1; }
	@test -f src/project.v || { echo "ERROR: missing src/project.v"; exit 1; }
	@test -f src/ascon_tt_perm_core.v || { echo "ERROR: missing src/ascon_tt_perm_core.v"; exit 1; }
	@test -f docs/info.md || { echo "ERROR: missing docs/info.md"; exit 1; }
	@test -f docs/architecture.md || { echo "ERROR: missing docs/architecture.md"; exit 1; }
	@test -f "$(ASCON_RTL_RTL)/ascon_round_comb.v" || { echo "ERROR: missing $(ASCON_RTL_RTL)/ascon_round_comb.v"; exit 1; }
	@test -f "$(ASCON_RTL_RTL)/ascon_perm_unrolled.v" || { echo "ERROR: missing $(ASCON_RTL_RTL)/ascon_perm_unrolled.v"; exit 1; }
	@bad="$$(find . -path ./.git -prune -o \( -name '*.rej' -o -name '*.orig' -o -name '*.patch' -o -name '*.zip' -o -name '*.tar.gz' \) -print)"; \
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
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated $(TT_DEBUG_PARAMS) -o $@ $(TEST_DIR)/tb_tt_perm_oracle.v $(SRC_FILES)

# ---------------------------------------------------------------------------
# TT-4A JOB BUFFER TEST
# ---------------------------------------------------------------------------

.PHONY: sim-job-buffers

sim-job-buffers: $(BUILD_DIR)/tb_tt_job_buffers.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_job_buffers.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_job_buffers.v | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated $(TT_DEBUG_PARAMS) -o $@ $(TEST_DIR)/tb_tt_job_buffers.v $(SRC_FILES)

# ---------------------------------------------------------------------------
# TT-4B FULL AEAD VECTOR TEST
# ---------------------------------------------------------------------------

.PHONY: sim-aead-vectors

$(ASCON_RTL_VEC_AD):
	$(MAKE) -C $(ASCON_RTL) vectors-ascon-c

sim-aead-vectors: $(BUILD_DIR)/tb_tt_aead_vectors.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_aead_vectors.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_aead_vectors.v $(ASCON_RTL_VEC_AD) | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated -o $@ $(TEST_DIR)/tb_tt_aead_vectors.v $(SRC_FILES)

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
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated \
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
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated \
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
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated \
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
