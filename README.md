# ASCON AEAD128 Tiny Tapeout project

Tiny Tapeout user macro implementing a bounded, byte-serial ASCON-AEAD128 accelerator.

## Start here

- Current project status: [`docs/overview.md`](docs/overview.md)
- Command map: [`docs/flow_guide.md`](docs/flow_guide.md)
- Run ledger: [`docs/run_ledger.md`](docs/run_ledger.md)
- Protocol: [`docs/protocol.md`](docs/protocol.md)
- DVC/hardening artifacts: [`docs/tt17_dvc_hardening_artifacts.md`](docs/tt17_dvc_hardening_artifacts.md)

## Current architecture

- `USE_SHARED_AEAD=1`: production/min-area shared single-permutation AEAD core.
- `USE_SHARED_AEAD=0`: preserved dual encrypt/decrypt reference bridge.
- `src/ascon_core/`: packaged ASCON RTL sourced from the sibling `ascon-rtl` project.

## Common commands

```sh
make sanity
make lint
make sim-aead-vectors-shared-prod-directout
make synth-prod-aead-shared-directout
make tt16-perf-cost
make docs-refresh
```

## 4x2 hardening capture

```sh
tools/tt17_capture_harden.sh --tiles 4x2 --clock-hz 10000000 --store min-area --name shared_4x2_10mhz --branch min-area --allow-dirty
```

## Generated outputs

- `build/` and `runs/` are local generated outputs.
- Large layout artifacts belong under `artifacts/hardening/...` and should be stored with DVC.
- Final GDS is present only after hardening reaches the final GDS export stage.

