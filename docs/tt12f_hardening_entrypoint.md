# TT-12F — Hardening entrypoint cleanup

This fixes four separate blockers:

1. `make sanity` was scanning `.venv/` and finding tarballs inside installed
   Python packages.
2. `tt10-flow-preflight` was using system `python3`, which did not have PyYAML.
3. `tt_tool.py --create-user-config` shells out to `yowasp-yosys`, so `.venv/bin`
   must be on `PATH`.
4. The first hardening path was running a heavier release regression that required
   ASCON C vector generation from a writable `../ascon-rtl` checkout. That is not
   required to start Tiny Tapeout hardening.

New flow:

```sh
make tt12-python-reset
make tt12-python-venv
make tt12-python-check
make tt12-pre-harden-check
make tt12-create-user-config
make tt12b-first-hardening-run
```

The full C-vector simulation can still be run separately once `../ascon-rtl` has
`external/ascon-c` available:

```sh
make sim-aead-vectors-prod-directout ASCON_RTL_WORKTREE=../ascon-rtl
```
