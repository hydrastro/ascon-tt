TOP := tt_um_ascon_aead
SRC_DIR := src
TEST_DIR := test
BUILD_DIR := build

ASCON_RTL ?= ../ascon-rtl
ASCON_RTL_RTL := $(ASCON_RTL)/rtl

IVERILOG ?= iverilog
VVP ?= vvp
VERILATOR ?= verilator
YOSYS ?= yosys

LOCAL_SRC_FILES := \
	$(SRC_DIR)/project.v \
	$(SRC_DIR)/ascon_tt_serial_frontend.v \
	$(SRC_DIR)/ascon_tt_aead_core_stub.v \
	$(SRC_DIR)/ascon_tt_perm_core.v

ASCON_RTL_FILES := \
	$(ASCON_RTL_RTL)/ascon_round_comb.v \
	$(ASCON_RTL_RTL)/ascon_perm_unrolled.v

SRC_FILES := $(LOCAL_SRC_FILES) $(ASCON_RTL_FILES)

.PHONY: all clean sim lint synth sanity

all: sim lint synth

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

sim: $(BUILD_DIR)/tb_tt_um_ascon_aead.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_um_ascon_aead.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_um_ascon_aead.v | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -o $@ $(TEST_DIR)/tb_tt_um_ascon_aead.v $(SRC_FILES)

lint:
	$(VERILATOR) --lint-only --timing -Wall -Wno-DECLFILENAME -I$(SRC_DIR) -I$(ASCON_RTL_RTL) --top-module $(TOP) $(SRC_FILES)

synth: | $(BUILD_DIR)
	$(YOSYS) -p 'read_verilog $(SRC_FILES); synth -top $(TOP); check; stat' > $(BUILD_DIR)/yosys_tt_scaffold_stat.txt
	cat $(BUILD_DIR)/yosys_tt_scaffold_stat.txt

sanity:
	@test -f info.yaml
	@test -f src/project.v
	@test -f src/ascon_tt_perm_core.v
	@test -f docs/info.md
	@test -f docs/architecture.md
	@test -f "$(ASCON_RTL_RTL)/ascon_round_comb.v"
	@test -f "$(ASCON_RTL_RTL)/ascon_perm_unrolled.v"
	@! find . -path ./.git -prune -o \( -name '*.rej' -o -name '*.orig' -o -name '*.patch' -o -name '*.zip' -o -name '*.tar.gz' \) -print | grep -q .
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
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -o $@ $(TEST_DIR)/tb_tt_perm_oracle.v $(SRC_FILES)

# ---------------------------------------------------------------------------
# TT-4A JOB BUFFER TEST
# ---------------------------------------------------------------------------

.PHONY: sim-job-buffers

sim-job-buffers: $(BUILD_DIR)/tb_tt_job_buffers.vvp
	$(VVP) $<

$(BUILD_DIR)/tb_tt_job_buffers.vvp: $(SRC_FILES) $(TEST_DIR)/tb_tt_job_buffers.v | $(BUILD_DIR)
	$(IVERILOG) -g2005-sv -I$(SRC_DIR) -I$(ASCON_RTL_RTL) -o $@ $(TEST_DIR)/tb_tt_job_buffers.v $(SRC_FILES)
