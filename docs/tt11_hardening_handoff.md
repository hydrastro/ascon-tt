# TT-11 — Hardening handoff

TT-11 prepares this repo for the actual Tiny Tapeout local hardening / GDS flow.

## What this phase checks

The preflight verifies:

- the top module is `tt_um_ascon_aead`;
- the top-level Tiny Tapeout ports exist;
- production defaults are active when `TT_DEBUG_DEFAULTS` is not defined;
- `info.yaml/source_files` points only to files inside this repo;
- vendored ASCON core RTL exists;
- Python/container/PDK/LibreLane environment pieces are visible;
- `tt/tt_tool.py` and `src/user_config.json` status.

## Commands

Run the local repo checks first:

```sh
make tt11-harden-preflight
```

Once `tt-support-tools` and the environment are installed:

```sh
./tt/tt_tool.py --create-user-config
./tt/tt_tool.py --harden
./tt/tt_tool.py --print-warnings
```

Make a source-only snapshot:

```sh
make tt11-snapshot
```

## Notes

Do not change `config.tcl` casually. The Tiny Tapeout documentation warns that
the OpenLane/LibreLane configuration is process-optimized and that design issues
should first be diagnosed through normal warnings/reports.

The generated GDS should be inspected only after the hardening run is clean
enough to trust. Magic/KLayout inspection is valuable, but it is not a substitute
for a clean automated DRC/LVS/timing/report flow.
