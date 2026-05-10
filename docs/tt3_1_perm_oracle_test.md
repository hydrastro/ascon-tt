# TT-3.1 — Permutation oracle integration test

This step hardens TT-3 by adding a full-state oracle comparison test.

The testbench instantiates:

- the Tiny Tapeout top-level serial shell
- a direct `ascon_perm_unrolled` oracle instance from `ascon-rtl`

Both receive the same 320-bit input state and 12-round request. The test then
reads all 40 output bytes back through the Tiny Tapeout byte protocol and checks
them against the direct oracle output.

This verifies:

- serial state byte load ordering
- `START_PERM` command behavior
- permutation done/status visibility
- state byte readback ordering
- full 320-bit output path through the TT shell

This does not independently prove the Ascon permutation algorithm; that remains
the responsibility of `ascon-rtl` tests. This test proves that the TT shell is
using the verified permutation core correctly.
