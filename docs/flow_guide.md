# Flow guide

This is the short command map. Historical phase notes remain in `docs/tt*.md`, but this file is the main entry point.

## Everyday

| target | present | purpose |
|---|---|---|
| `sanity` | yes | repo hygiene and required files |
| `lint` | yes | Verilator lint |
| `debug-regression` | yes | debug/permutation regression suite |
| `prod-default-check` | yes | production functional smoke check |

## Simulation

| target | present | purpose |
|---|---|---|
| `sim` | yes |  |
| `sim-perm-oracle` | yes |  |
| `sim-job-buffers` | yes |  |
| `sim-aead-vectors-prod-directout` | yes |  |
| `sim-aead-vectors-shared-prod-directout` | yes | shared-core AEAD vector test |
| `sim-aead-vectors-dual-ref-directout` | yes | old dual-core reference vector test |
| `sim-perf-cycles` | yes |  |

## Area/profile

| target | present | purpose |
|---|---|---|
| `synth` | yes |  |
| `synth-prod-aead-top-directout` | yes |  |
| `synth-prod-aead-shared-directout` | yes | Yosys shared-core production synthesis |
| `synth-dual-ref-directout` | yes | Yosys dual reference synthesis |
| `tt14d-shared-report` | yes |  |
| `tt16-perf-cost` | yes | measured cycles and cost/perf model |

## Hardening

| target | present | purpose |
|---|---|---|
| `tt12-create-user-config` | yes |  |
| `tt12-harden` | yes | run Tiny Tapeout hardening flow |
| `tt12-create-png` | yes |  |
| `tt17-capture-harden` | no | set config, harden, capture artifacts, optional DVC |

## Artifact/docs

| target | present | purpose |
|---|---|---|
| `tt15-find-gds` | yes |  |
| `docs-refresh` | yes | regenerate overview, ledger, and flow guide |
| `docs-ledger` | yes |  |

