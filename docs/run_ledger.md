# Run ledger

_Generated: 2026-05-11T04:22:11Z_

## Functional/synthesis milestones

| milestone | result | evidence |
|---|---|---|
| old prod directout sim | PASS | `build/tt14d_smoke/summary.md` |
| shared prod directout sim | PASS | `build/tt14d_smoke/summary.md` |
| shared-vs-dual synth compare | PASS | `build/tt14d_synth_compare/profile_compare.txt` |

## Hardening/artifact runs

| run | tiles | clock Hz | rc | utilization | GDS | notes |
|---|---|---:|---:|---:|---|---|
| `min-area/shared_4x2_10mhz` | 4x2 | 10000000 | 2 | 218.023% | no | failed before GDS export |
| `min-area/shared_4x2_25mhz` | 4x2 | 25000000 | 2 | 218.023% | no | failed before GDS export |

