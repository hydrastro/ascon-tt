# ASCON TT project overview

_Generated: 2026-05-11T04:22:11Z_

## Current technical status

- Full bounded ASCON-AEAD128 encrypt/decrypt is implemented behind the Tiny Tapeout byte-serial frontend.
- The minimum-area candidate is the shared single-permutation core selected by `USE_SHARED_AEAD=1`.
- The old dual encrypt/decrypt bridge is preserved as `USE_SHARED_AEAD=0` reference RTL.
- Production/hardening defaults should use the shared core; reference targets explicitly force the dual bridge.

## Key result

| profile | Yosys cells | DFF | MUX | XOR | XNOR |
|---|---:|---:|---:|---:|---:|
| old dual directout | 31268 | 4479 | 3662 | 2725 | 1686 |
| shared directout | 19553 | 2891 | 2366 | 1493 | 807 |
| reduction | 11715 |  |  |  |  |

Cell reduction: **37.47%**.

## Physical-design status

No final GDS is present unless a hardening run reaches the final GDS export stage. If a run fails at global placement, only intermediate DEF/ODB files are expected.

| run | tiles | clock Hz | harden rc | utilization | GDS |
|---|---|---:|---:|---:|---|
| `min-area/shared_4x2_10mhz` | 4x2 | 10000000 | 2 | 218.023% | no |
| `min-area/shared_4x2_25mhz` | 4x2 | 25000000 | 2 | 218.023% | no |

## Next run

Rerun 4x2 after confirming `USE_SHARED_AEAD=1` is the production default:

```sh
tools/tt17_capture_harden.sh --tiles 4x2 --clock-hz 10000000 --store min-area --name shared_4x2_10mhz_rerun --branch min-area --allow-dirty
```

