# GF26a bring-up: clone → RTL checks → GDSII

This is the working path for the cleaned ASCON-TT GF26a repository.

## 0. Start from a clean branch

```sh
git clone https://github.com/hydrastro/ascon-tt.git
cd ascon-tt
git checkout -b gf26a-cleanup
```

Apply the cleaned tree/patch, then initialize the TT support submodule:

```sh
git submodule sync --recursive
git submodule update --init --recursive
```

## 1. Enter the Nix dev shell

```sh
nix develop
```

This shell sets:

```sh
PDK=gf180mcuD
PDK_ROOT=$PWD/.ttsetup/pdk
LIBRELANE_TAG=3.0.0
```

Stay inside this shell for the remaining steps.

## 2. Create the Python tool environment

```sh
make tt12-python-venv
make tt12-python-check
```

## 3. Functional verification

Run both AEAD variants before attempting hardening:

```sh
make gen-vectors-128a sim-128a
make gen-vectors-128  sim-128
```

Both simulations must pass.  If either fails, stop and fix RTL first.

## 4. Generic synthesis profiling

```sh
make synth-all
make tt5-profiles
```

Use this to compare area for:

- ASCON-128a, `ROUNDS_PER_CYCLE=1`
- ASCON-128a, `ROUNDS_PER_CYCLE=8`
- ASCON-128, `ROUNDS_PER_CYCLE=1`
- ASCON-128, `ROUNDS_PER_CYCLE=8`

For GF26a, start with `ROUNDS_PER_CYCLE=1`; the 8-round-per-cycle version is only for exploration if area permits.

## 5. Set GF26a configuration

Recommended starting point:

```sh
python3 tools/tt15_set_tt_config.py   --pdk gf180mcuD   --tiles 4x4   --clock-hz 10000000   --variant 1   --rpc 1
```

Variant meanings:

- `--variant 1` = ASCON-128a
- `--variant 0` = ASCON-128

## 6. Harden to GDSII

```sh
make harden-128a-gf26a
```

Or manually:

```sh
make tt12-write-user-config
make tt12-harden
```

This uses the TT support tool with `--gf --no-docker`, so it expects the Nix shell and a usable local LibreLane/PDK setup.

## 7. Inspect result

```sh
make tt12-print-stats
make tt12-print-warnings
make tt15-find-gds
make tt12-create-tt-submission
```

The GDS should appear under `runs/wokwi/final/gds/` or be printed by `make tt15-find-gds`.

## 8. CI / source-of-truth flow

Push the branch to GitHub and run the `gds` workflow.  The workflow uses:

```yaml
uses: TinyTapeout/tt-gds-action@ttgf26a
with:
  pdk: gf180mcuD
```

Treat the CI artifact and precheck as the final acceptance path for GF26a.

## 9. If hardening fails

Typical fixes:

- Placement/utilization failure: keep `4x4`, keep `ROUNDS_PER_CYCLE=1`, reduce buffering/state, or split debug/reference code from production synthesis.
- Setup timing failure: lower `clock_hz` to 5 MHz or 2 MHz.
- Hold timing failure: increase hold slack margins in `src/config.json`.
- Wrong template error: confirm `FP_DEF_TEMPLATE` ends with `_pgvdd.def`, not `_pg.def`.
- Missing PDK: use the GitHub Action as source of truth, or install the GF180 PDK under `$PDK_ROOT` with the same version expected by Tiny Tapeout.
