# TT-13 — Area fit plan after GPL-0301

The first physical-flow failure is now real:

```text
[GPL-0301] Utilization ... exceeds 100%
```

This is not an environment problem. It means the standard cells do not fit in
the selected Tiny Tapeout placement region.

## What not to do

Do not try to fix this by only changing `PL_TARGET_DENSITY_PCT`.

The Tiny Tapeout template says `PL_TARGET_DENSITY_PCT` can be increased when
global placement fails with congestion-style density problems, but a utilization
above 100% is an absolute area problem: the cells physically exceed the region.

## What this means for the current ASCON design

The current production full-AEAD design instantiates a relatively large full
encrypt/decrypt architecture. If the project is already at `tiles: "8x2"`, there
is no larger standard Tiny Tapeout tile setting in the current template.

Near-term options:

1. **Do not change architecture; try a marginal fit experiment.**
   This is unlikely to be robust because the current run is already above 100%.
   Even if it passes global placement, routing/timing may fail.

2. **Submit a reduced feature design.**
   Examples: encrypt-only AEAD, decrypt-only AEAD, or permutation-only debug
   macro. These fit much more comfortably, but they are not full AEAD.

3. **Keep full AEAD and redesign the datapath.**
   This is the preferred technical path:
   - one shared 320-bit ASCON permutation datapath;
   - one AEAD controller for encrypt/decrypt mode;
   - no separate full encrypt and decrypt cores instantiated at the same time;
   - minimal output buffering;
   - serial byte frontend retained.

4. **Use a larger/non-Tiny-Tapeout target.**
   If full AEAD with the current dual-core architecture is required unchanged,
   move it to a larger shuttle/macro flow or FPGA/NEORV32 accelerator target.

## Command

After a failed hardening run:

```sh
make tt13-area-report
```

or:

```sh
python3 tools/tt13_area_fit_report.py runs/wokwi
```
