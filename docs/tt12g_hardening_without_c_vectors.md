# TT-12G — First hardening without ASCON C-vector regeneration

The first Tiny Tapeout hardening entrypoint must not depend on the full release
regression because that regression regenerates ASCON C vectors through the
separate `../ascon-rtl` checkout.

That checkout may not have `external/ascon-c`, and the flake input path can be
read-only. Neither is required for GDS hardening because the TT repo already
packages the synthesizable RTL under `src/ascon_core/`.

The hardening entrypoint now runs:

```sh
make tt12-pre-harden-check
make tt12-create-user-config
make tt12-harden
make tt12b-after-harden
```

where `tt12-pre-harden-check` performs only:

```sh
make sanity
make tt10-flow-preflight
make tt11b-tools-check
make tt12-python-check
make lint
make synth
```

The full C-vector regression remains available separately:

```sh
make sim-aead-vectors-prod-directout ASCON_RTL_WORKTREE=../ascon-rtl
```

but it requires `../ascon-rtl/external/ascon-c` or a suitable `ASCON_C_DIR`.
