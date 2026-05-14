# ASCON-TT GDSII Generation — Complete Guide

This guide goes from a fresh clone to a GDSII in the fewest working steps.

---

## Prerequisites

- NixOS with Nix flakes enabled (or any Linux with Nix installed)
- Git
- ~10 GB disk (PDK download)

---

## Step 1 — Clone

```sh
git clone <your-repo-url> ascon-tt
cd ascon-tt
git submodule update --init --recursive   # pulls the tt/ tooling submodule
```

---

## Step 2 — Enter the Nix dev shell

```sh
nix develop
```

This gives you: yosys, iverilog, verilator, openroad, klayout, python3 + tkinter.
**Stay in this shell for all subsequent commands.**

---

## Step 3 — Verify RTL (no toolchain needed)

```sh
make gen-vectors-128a && make sim-128a    # MUST print: TESTS PASSED
make gen-vectors-128  && make sim-128     # MUST print: TESTS PASSED
```

If either fails, the RTL has a bug. Do not proceed to hardening.

---

## Step 4 — Gate count estimates (no PDK needed)

```sh
make synth-all        # runs all 4 configurations, prints cell counts
make tt5-profiles     # same but structured table
```

---

## Step 5 — Choose your target configuration

Run `python3 tools/tt15_set_tt_config.py` with your chosen tile/clock/variant:

```sh
# ASCON-128a, min-area (recommended starting point):
python3 tools/tt15_set_tt_config.py --tiles 8x2 --clock-hz 10000000 --variant 1 --rpc 1

# ASCON-128a, max-perf:
python3 tools/tt15_set_tt_config.py --tiles 10x2 --clock-hz 50000000 --variant 1 --rpc 8

# ASCON-128, min-area:
python3 tools/tt15_set_tt_config.py --tiles 6x2 --clock-hz 10000000 --variant 0 --rpc 1

# ASCON-128, max-perf:
python3 tools/tt15_set_tt_config.py --tiles 8x2 --clock-hz 50000000 --variant 0 --rpc 8
```

This updates `src/config.json` and `info.yaml` atomically.

---

## Step 6 — Install the Python venv (once per machine)

```sh
make tt12-python-venv
```

Then install the sky130A PDK (also once):

```sh
.venv/bin/python -m librelane --pdk-root .ttsetup/pdk
# The final "No config file" error is NORMAL — ignore it. The PDK is downloaded.
```

---

## Step 7 — Harden → GDSII

```sh
make tt12-harden
```

This runs the full LibreLane/OpenLane 2 flow. Takes 10–30 minutes.
No Docker or Podman required (`LIBRELANE_DOCKERLESS=1` is set automatically).

**One-shot shortcuts** (set config + harden in one command):

```sh
make harden-128a-minarea     # ASCON-128a · 8x2 tiles · 10 MHz
make harden-128a-maxperf     # ASCON-128a · 10x2 tiles · 50 MHz
make harden-128-minarea      # ASCON-128  · 6x2 tiles · 10 MHz
make harden-128-maxperf      # ASCON-128  · 8x2 tiles · 50 MHz
```

---

## Step 8 — Inspect the result

```sh
make tt12-print-stats        # area utilization and timing slack
make tt12-print-warnings     # any DRC/LVS warnings
make tt15-find-gds           # prints path to the .gds file
make tt12-create-png         # generates a layout image
make tt16-perf-cost          # throughput estimate for current config
```

---

## Step 9 — Tile/clock sizing (if harden fails)

```sh
# Sweep multiple tile sizes and clocks; reads from info.yaml for variant/rpc:
TT_SWEEP_TILES="6x2 8x2 10x2" \
TT_SWEEP_FREQS="10000000 25000000 50000000" \
make tt15-sweep
# Results in: artifacts/runs/tt15_sweep_<timestamp>/summary.md
```

Interpret results:
- `harden_passed` → good, use this tile+clock
- `error` / `failed` → area overflow or timing violation; try larger tiles or lower clock

---

## GF180 variant

Install the GF180 PDK:
```sh
.venv/bin/python -m volare enable \
    --pdk gf180mcuD \
    --pdk-root .ttsetup/pdk \
    e0f692f46654d6c7c99fc70a0c94a080dab53571
```

Then harden with:
```sh
python3 tools/tt15_set_tt_config.py --tiles 8x2 --clock-hz 10000000 --variant 1 --rpc 1 --pdk gf180mcuD
make tt12-harden PDK=gf180mcuD
```

Also update `src/config.json` manually:
```json
"FP_DEF_TEMPLATE": "dir::../tt/tech/gf180mcuD/def/tt_block_8x2_pg.def"
```

---

## Quick reference — full flow

```sh
git clone <repo> ascon-tt && cd ascon-tt
git submodule update --init --recursive
nix develop                               # stay in this shell

make gen-vectors-128a && make sim-128a    # verify
make synth-all                            # gate counts

python3 tools/tt15_set_tt_config.py \
    --tiles 8x2 --clock-hz 10000000 --variant 1 --rpc 1

make tt12-python-venv
.venv/bin/python -m librelane --pdk-root .ttsetup/pdk  # install PDK once

make tt12-harden                          # generate GDSII

make tt12-print-stats
make tt15-find-gds
make tt12-create-png
```

---

## What each command does

| Command | What it does |
|---------|-------------|
| `make gen-vectors-128a` | Generate ASCON-128a test vectors (Python, no external tools) |
| `make sim-128a` | Run functional simulation (iverilog) |
| `make synth` | Yosys generic synthesis, prints cell count |
| `make tt5-profiles` | All 4 configurations in one table |
| `python3 tools/tt15_set_tt_config.py ...` | Update config.json + info.yaml for one target |
| `make tt12-python-venv` | Create .venv with tt tooling + librelane |
| `make tt12-harden` | Full LibreLane GDSII flow |
| `make tt12-print-stats` | Area utilization + timing from last run |
| `make tt15-find-gds` | Locate the generated .gds file |
| `make tt12-create-png` | Layout PNG from klayout |
| `make tt16-perf-cost` | Throughput estimate (MB/s) for current config |
| `make tt15-sweep` | Try multiple tile+clock combos |
