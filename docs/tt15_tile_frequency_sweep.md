# TT-15 — Tile/frequency sweep

The shared single-permutation AEAD path reduced Yosys cells from 31,268 to
19,553, a 37.47% reduction. The next step is physical exploration.

## Tile sizes

Tiny Tapeout digital projects use discrete tile sizes such as:

```text
1x1, 1x2, 2x2, 3x2, 4x2, 6x2, 8x2
```

The count is width × height. For example:

| setting | tile count |
|---|---:|
| `4x2` | 8 |
| `6x2` | 12 |
| `8x2` | 16 |

There is no normal `8x8` Tiny Tapeout project tile setting.

## First recommended sweep

Start with:

```sh
TT_SWEEP_TILES="6x2 4x2 8x2" \
TT_SWEEP_FREQS="10000000 25000000 5000000" \
tools/tt15_tile_freq_sweep.sh
```

Interpretation:

- `6x2 @ 10 MHz`: first cost-reduction target;
- `6x2 @ 25 MHz`: likely useful if routing/timing are okay;
- `4x2 @ 5–10 MHz`: aggressive cost target;
- `8x2`: fallback/reference, expected to fit after the shared-core area cut.

## GDS files

GDS files are generated only after hardening reaches the final layout stage.
Search with:

```sh
tools/tt15_find_gds.sh
```

Typical candidates are under `runs/` after a successful hardening run. If
global placement fails, there may be no final GDS yet.
