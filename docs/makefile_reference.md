# Makefile target reference

This file explains the main targets. For a generated list of every target, run:

```sh
make list-targets
```

## Everyday targets

| target | use |
|---|---|
| `make help` | print common commands |
| `make sanity` | check required files and reject stale archives/patch rejects |
| `make lint` | run Verilator lint |
| `make synth` | run Yosys synthesis of the current Tiny Tapeout top |
| `make clean` | remove local build outputs |

## Simulation targets

| target | use |
|---|---|
| `make sim` | debug frontend/permutation integration simulation |
| `make sim-perm-oracle` | standalone permutation oracle test |
| `make sim-job-buffers` | frontend job-buffer test |
| `make sim-aead-vectors` | full AEAD vector test using default parameters |
| `make sim-aead-vectors-prod-directout` | full AEAD vector test using production direct-output profile |
| `make debug-regression` | runs debug-oriented simulation tests |

## Synthesis/profile targets

| target | use |
|---|---|
| `make tt5-profiles` | generate synthesis profile matrix |
| `make tt5-report` | print profile table from generated Yosys logs |
| `make synth-prod-aead-top` | synthesize production AEAD top |
| `make synth-prod-aead-top-directout` | synthesize production direct-output top |
| `make prod-default-report` | summarize production Yosys output |
| `make tt13-area-report` | parse hardening logs and compute fit margin |

## Release/hardening targets

| target | use |
|---|---|
| `make tt10-flow-preflight` | check TT packaging assumptions |
| `make tt11-harden-preflight` | check hardening handoff assumptions |
| `make tt12-python-venv` | create local Python env for TT support tools |
| `make tt12-python-check` | verify Python/KLayout/Cairo/LibreLane/Yosys wrapper imports |
| `make tt12-create-user-config` | generate TT/LibreLane merged user config |
| `make tt12-harden` | run Tiny Tapeout hardening |
| `make tt12b-after-harden` | collect warnings/stats/triage after a completed run |

## Historical phase targets

The Makefile contains many `tt7*`, `tt8*`, `tt9*`, `tt10*`, and `tt12*` targets.
These were created during bring-up. Treat them as historical/profiling targets
unless they are listed above.

For new development, prefer:

```sh
make sanity
make lint
make synth
make sim-aead-vectors-prod-directout
make tt5-profiles
make tt13-area-report
```
