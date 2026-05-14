# ASCON AEAD128 / AEAD128a for Tiny Tapeout GF26a

This repository contains a Tiny Tapeout user macro for ASCON AEAD using a byte-serial TT interface.  The production path targets the GF26a shuttle (`gf180mcuD`) and uses a shared ASCON permutation/datapath instead of separate encrypt/decrypt datapaths.

## Current intended production configuration

- Shuttle / PDK: Tiny Tapeout GF26a, `gf180mcuD`
- Top module: `tt_um_ascon_aead`
- Area template: `4x4` GF180 TT block (`tt_block_4x4_pgvdd.def`)
- Default clock: 10 MHz (`CLOCK_PERIOD = 100 ns`)
- Default variant: ASCON-128a (`ASCON_VARIANT=1`)
- Datapath: shared AEAD core (`USE_SHARED_AEAD=1`)
- Performance/area knob: `ROUNDS_PER_CYCLE`, default `1` for minimum area

## Repository layout

| Path | Purpose |
|---|---|
| `src/project.v` | Tiny Tapeout top module |
| `src/ascon_tt_serial_frontend.v` | byte-serial command/response protocol |
| `src/ascon_tt_aead_shared.v` | shared-datapath AEAD engine for ASCON-128 and ASCON-128a |
| `src/ascon_tt_aead_bridge.v` | wrapper selecting shared or reference bridge |
| `src/ascon_tt_aead_bridge_dual.v` | larger dual-core reference implementation |
| `src/ascon_core/` | packaged ASCON RTL primitives/reference cores |
| `test/` | Icarus testbenches |
| `tools/` | vector generation, config, hardening, and reporting helpers |
| `.github/workflows/gds.yaml` | canonical GF26a GDS/precheck action |

## Fast path on NixOS

```sh
git clone https://github.com/hydrastro/ascon-tt.git
cd ascon-tt
git checkout -b gf26a-cleanup
# apply this cleaned tree/patch, then:
git submodule update --init --recursive
nix develop

make tt12-python-venv
make gen-vectors-128a sim-128a
make gen-vectors-128  sim-128
make synth-all
make harden-128a-gf26a
make tt12-print-stats
make tt15-find-gds
```

The canonical CI path is the GitHub Actions workflow in `.github/workflows/gds.yaml`, which uses `TinyTapeout/tt-gds-action@ttgf26a` with `pdk: gf180mcuD`.

## Important warning

Do not use SKY130 tile templates such as `tt_block_8x2_pg.def` for GF26a.  In the current GF180 TT support tree the GF templates use names like `tt_block_4x4_pgvdd.def`, and the available GF sizes are `1x1`, `1x2`, `2x2`, `3x2`, `3x4`, `4x2`, and `4x4`.
