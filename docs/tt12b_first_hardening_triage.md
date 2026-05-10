# TT-12B — First hardening run and triage

TT-12B wraps the first local Tiny Tapeout hardening attempt and adds a triage
step before manual GDS inspection.

## Why this exists

Generated GDS is useful, but the first decision after hardening should come from
reports:

- Did synthesis emit serious warnings?
- Did the run produce DRC/LVS/antenna/timing errors?
- What run directory was produced?
- Which artifacts should be captured and compared later?

## Commands

Run the full first-hardening wrapper:

```sh
make tt12b-first-hardening-run
```

If hardening was already run, only perform post-run triage and capture:

```sh
make tt12b-after-harden RUN_DIR=<actual-run-dir> RUN_NAME=first_harden
```

If the run directory is unknown:

```sh
python3 tools/tt12b_find_run_dir.py runs build
```

Generated local outputs:

- `build/tt12b/tt_print_warnings.log`
- `build/tt12b/tt_print_stats.log`
- `build/tt12b/tt_print_cell_category.log`
- `build/tt12b/triage.md`
- `artifacts/runs/<timestamp>_<gitsha>_<pdk>_<name>/`
- `artifacts/manifests/<timestamp>_<gitsha>_<pdk>_<name>.json`

## Manual inspection order

1. `build/tt12b/triage.md`
2. Tiny Tapeout warning printout
3. stats and cell categories
4. detailed reports under the run directory
5. only then inspect GDS in KLayout/Magic

A visually plausible GDS is not enough. The automated reports decide whether the
layout is physically meaningful.
