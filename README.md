# ASCON AEAD128 Tiny Tapeout project

This repository contains a Tiny Tapeout user macro for an ASCON AEAD128 serial
accelerator.

The current RTL is functionally useful, but the current full-AEAD production
architecture is too large for the selected Tiny Tapeout macro area. The first
hardening attempt reached global placement and failed because placement
utilization was greater than 100%.

## Current status

Known-good functional direction:

- byte-serial Tiny Tapeout frontend;
- full ASCON AEAD128 command protocol;
- packaged ASCON RTL under `src/ascon_core/`;
- Yosys/Verilator/Icarus simulation and synthesis targets;
- Tiny Tapeout hardening flow reaches global placement.

Known physical-design problem:

- current production full-AEAD top uses a dual encrypt/decrypt bridge;
- the design exceeded placement area at about 107% utilization;
- a credible routable target needs roughly 16–26% movable area reduction;
- the next architecture should use one shared ASCON permutation/datapath.

## Repository layout

| path | purpose |
|---|---|
| `src/project.v` | Tiny Tapeout top module `tt_um_ascon_aead` |
| `src/ascon_tt_serial_frontend.v` | byte-serial command/response frontend |
| `src/ascon_tt_aead_bridge.v` | current dual-core AEAD bridge/reference implementation |
| `src/ascon_tt_perm_core.v` | standalone permutation debug/oracle path |
| `src/ascon_core/` | packaged ASCON RTL used by TT flow |
| `test/` | Icarus Verilog testbenches |
| `tools/` | report, audit, and helper scripts |
| `docs/` | architecture notes and flow history |
| `tt/` | Tiny Tapeout support tools checkout/submodule |
| `build/` | generated local build outputs; do not commit |
| `runs/` | generated hardening runs; do not commit |
| `artifacts/runs/` | captured generated layout artifacts; normally use DVC or external storage |

## Quick start

Inside the Nix shell:

```sh
nix develop
make help
make sanity
make lint
make synth
```

Useful simulation/profile checks:

```sh
make debug-regression
make sim-aead-vectors-prod-directout
make tt5-profiles
```

Hardening-oriented checks:

```sh
make tt12-python-check
make tt12-create-user-config
make tt12-harden
make tt13-area-report
```

If a generated vector header is missing, the full AEAD vector target may need a
writable `ascon-rtl` checkout with `external/ascon-c` available:

```sh
make sim-aead-vectors-prod-directout ASCON_RTL_WORKTREE=../ascon-rtl
```

## What should be committed

Commit:

- `src/`
- `test/`
- `tools/`
- `docs/`
- `Makefile`
- `README.md`
- `info.yaml`
- `src/config.json`
- small artifact manifests under `artifacts/manifests/`

Do not commit:

- `.venv/`
- `build/`
- `runs/`
- generated `.gds`, `.def`, `.spef`, `.sdf`, `.mag`
- generated vector headers under `sim/generated/`
- patch/archive leftovers such as `.patch`, `.zip`, `.tar.gz`, `.orig`, `.rej`

## Minimum-area full AEAD direction

The current implementation is a correct reference direction, not the final
minimum-area TT architecture. For a compact complete ASCON AEAD128 macro, move to:

1. one 320-bit ASCON state register;
2. one `ascon_perm_unrolled` instance;
3. one AEAD FSM that handles encrypt and decrypt modes;
4. no simultaneous full `ascon_aead128_enc_ad` and `ascon_aead128_dec_ad`
   instances in the production path;
5. same byte-serial frontend protocol and same vector tests.

Keep the existing bridge as the functional reference until the shared core
passes the full AEAD vector tests.

## Suggested next branch

```sh
git checkout -b tt14-shared-aead
```

Do not start by deleting the old bridge. First add a new shared core and compare
it against the current bridge.
