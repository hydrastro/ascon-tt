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
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated -o $@ $(TEST_DIR)/tb_tt_um_ascon_aead.v $(SRC_FILES)

lint:
	$(VERILATOR) --lint-only --timing -Wall -Wno-DECLFILENAME -I$(SRC_DIR) -I$(ASCON_RTL_RTL) --top-module $(TOP) $(SRC_FILES)

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
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated -o $@ $(TEST_DIR)/tb_tt_perm_oracle.v $(SRC_FILES)

# ---------------------------------------------------------------------------
# TT-4A JOB BUFFER TEST
# ---------------------------------------------------------------------------

.PHONY: sim-job-buffers

sim-job-buffers: $(BUILD_DIR)/tb_tt_job_buffers.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_job_buffers.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_job_buffers.v | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -I$(ASCON_RTL)/sim/generated -o $@ $(TEST_DIR)/tb_tt_job_buffers.v $(SRC_FILES)

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

tt5-profiles: tt5-full-debug tt5-full-aead-bridge tt5-enc-only tt5-dec-only tt5-perm-debug tt5-perm-core $(TT5_DIR)/full_aead_top.txt
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
