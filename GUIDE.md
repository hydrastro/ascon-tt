# ASCON-TT GDSII Generation Guide

## Prerequisites

- NixOS or Nix package manager installed
- Git
- ~10 GB disk space (PDK download)

---

## 1. Clone and set up

```sh
git clone <your-repo-url> ascon-tt
cd ascon-tt
git submodule update --init --recursive   # pulls the tt/ tooling submodule
nix develop                               # drops you into the reproducible dev shell
```

---

## 2. Verify RTL correctness

```sh
make gen-vectors-128a      # generate ASCON-128a test vectors
make gen-vectors-128       # generate ASCON-128 test vectors

make sim-128a              # MUST print: ASCON TT FULL AEAD VECTOR TESTS PASSED
make sim-128               # MUST print: ASCON TT FULL AEAD VECTOR TESTS PASSED
# (guide alias also works:)
make sim-aead-vectors-shared-prod-directout   # → same as sim-128a
```

---

## 3. Synthesis estimates (Yosys, no PDK needed)

```sh
# Quick cell count for one configuration:
make synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1   # 128a min-area
make synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=8   # 128a max-perf
make synth ASCON_VARIANT=0 ROUNDS_PER_CYCLE=1   # 128  min-area
make synth ASCON_VARIANT=0 ROUNDS_PER_CYCLE=8   # 128  max-perf
# All four at once:
make synth-all

# Profile matrix (all 4 configs → build/tt5/*.txt):
make tt5-clean
make tt5-profiles
# Results are printed automatically. Reprint anytime:
make tt5-report
```

---

## 4. Performance / cost model

```sh
# After synth, run the latency model:
make tt16-perf-cost ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1
cat build/tt16/perf_cost_report.md
```

---

## 5. Choose tile size and clock

Edit these parameters together. The relationship is:
- `CLOCK_PERIOD` (in config.json) = `1e9 / clock_hz`  (e.g. 25 MHz → 40 ns)
- Tile area must fit the design; start at 6x2 for 128a-minarea.

```sh
# Set tile + clock in one command (updates src/config.json + info.yaml):
python3 tools/tt15_set_tt_config.py --tiles 6x2 --clock-hz 25000000   --variant 1 --rpc 1

# Then re-synth to check timing at the new clock:
make synth ASCON_VARIANT=1 ROUNDS_PER_CYCLE=1
```

**Recommended starting points:**

| Config           | Tiles | Clock    | ASCON_VARIANT | RPC |
|------------------|-------|----------|---------------|-----|
| 128a min-area    | 6x2   | 10 MHz   | 1             | 1   |
| 128a max-perf    | 8x2   | 50 MHz   | 1             | 8   |
| 128  min-area    | 4x2   | 10 MHz   | 0             | 1   |
| 128  max-perf    | 6x2   | 50 MHz   | 0             | 8   |

### Optional: tile/frequency sweep

```sh
# Sweeps multiple tile+clock combos; results in artifacts/runs/tt15_sweep_<ts>/summary.md
TT_SWEEP_TILES="6x2 4x2 8x2" \
TT_SWEEP_FREQS="10000000 25000000 50000000" \
make tt15-sweep
```

Outcomes per cell:
- `area_overflow`  → design doesn't fit; use larger tiles
- `timing_issue`   → fits but misses timing; lower the clock
- `harden_passed`  → good candidate for submission

---

## 6. Manual config.json tuning (if needed)

```sh
nano src/config.json
```

Key fields:
```json
{
  "CLOCK_PERIOD": 40,
  "FP_DEF_TEMPLATE": "dir::../tt/tech/sky130A/def/tt_block_6x2_pg.def",
  "VERILOG_DEFINES": [
    "USE_SHARED_AEAD=1",
    "ASCON_VARIANT=1",
    "ROUNDS_PER_CYCLE=1",
    "ENABLE_OUT_BUFFER=0",
    "ENABLE_DIAGNOSTICS=0",
    "ENABLE_PERM_DEBUG=0"
  ]
}
```

For GF180: `"FP_DEF_TEMPLATE": "dir::../tt/tech/gf180mcuD/def/tt_block_8x2_pg.def"`

---

## 7. Pre-harden checks

```sh
make sanity                        # lint + quick synth, no Python needed
make lint                          # Verilator lint only

make sim-128a                      # regression test (must pass)
make sim-128                       # regression test (must pass)
```

---

## 8. Python venv (needed for hardening)

```sh
make tt12-python-reset             # wipe old venv if upgrading
make tt12-python-venv              # create venv + install requirements + librelane

# Verify the environment is healthy:
make tt12-python-check
```

---

## 9. Install the PDK

```sh
# Sky130A (default):
.venv/bin/python -m librelane --pdk-root .ttsetup/pdk

# GF180 (alternative):
.venv/bin/python -m volare enable --pdk gf180mcuD \
  --pdk-root .ttsetup/pdk <version>
# Or just set PDK=gf180mcuD; librelane will download on first harden run.
```

---

## 10. Final pre-harden check

```sh
make tt12-pre-harden-check         # python-check + lint + synth in one shot
```

---

## 11. Generate user config

```sh
make tt12-create-user-config
```

This creates `src/user_config.json` from `src/config.json`.  Check for warnings:

```sh
make tt12-print-warnings
```

---

## 12. HARDEN → generate GDSII

```sh
make tt12-harden
```

This runs LibreLane (OpenLane 2) inside a Nix sandbox. It takes 10-30 minutes.
No Docker or Podman needed (`LIBRELANE_DOCKERLESS=1` is set automatically).

### One-command four-config hardening:

```sh
make harden-128a-minarea     # ASCON-128a, 6x2 tiles, 10 MHz
make harden-128a-maxperf     # ASCON-128a, 8x2 tiles, 50 MHz
make harden-128-minarea      # ASCON-128,  4x2 tiles, 10 MHz
make harden-128-maxperf      # ASCON-128,  6x2 tiles, 50 MHz
```

---

## 13. After hardening

```sh
# Print stats and check for violations:
make tt12-print-stats
make tt12-print-warnings
make tt12-print-cell-category

# Find the GDS file:
make tt15-find-gds
# → prints something like: runs/wokwi/final/gds/tt_um_ascon_aead.gds

# Area fit check:
make tt13-area-report
cat build/tt13/area_fit_report.md

# Generate PNG layout preview:
make tt12-create-png
```

---

## 14. Capture the artifact

```sh
make tt17-capture \
  TILES=6x2 CLOCK_HZ=10000000 \
  NAME=shared_128a_6x2_10mhz \
  ALLOW_DIRTY=1
```

Artifacts land in `artifacts/runs/`.

---

## Changing PDK or parameters mid-flow

```sh
# Example: GF180, 4x2 tiles, 25 MHz:
python3 tools/tt15_set_tt_config.py --tiles 4x2 --clock-hz 25000000 \
  --variant 1 --rpc 1

make tt12-pre-harden-check \
  PDK=gf180mcuD \
  PDK_ROOT=/opt/pdk \
  LIBRELANE_TAG=3.0.0rc1

make tt12-harden \
  PDK=gf180mcuD \
  PDK_ROOT=/opt/pdk \
  LIBRELANE_TAG=3.0.0rc1
```

In `src/config.json` for GF180:
```json
"FP_DEF_TEMPLATE": "dir::../tt/tech/gf180mcuD/def/tt_block_8x2_pg.def"
```

---

## Quick reference — full flow for one config

```sh
git clone <repo> ascon-tt && cd ascon-tt
git submodule update --init --recursive
nix develop

make gen-vectors-128a && make sim-128a       # verify RTL
make synth-all                               # gate counts

python3 tools/tt15_set_tt_config.py \
  --tiles 6x2 --clock-hz 10000000 \
  --variant 1 --rpc 1

make tt12-python-venv
.venv/bin/python -m librelane --pdk-root .ttsetup/pdk   # install PDK once

make tt12-pre-harden-check
make tt12-create-user-config
make tt12-harden

make tt12-print-stats
make tt15-find-gds
make tt12-create-png
make tt17-capture TILES=6x2 CLOCK_HZ=10000000 NAME=128a_minarea ALLOW_DIRTY=1
```
