# TT-10B — Packaged ASCON core RTL

TT-10B vendors the minimal ASCON RTL dependency set into this Tiny Tapeout repo:

- `src/ascon_core/ascon_round_comb.v`
- `src/ascon_core/ascon_perm_unrolled.v`
- `src/ascon_core/ascon_aead128_enc_ad.v`
- `src/ascon_core/ascon_aead128_dec_ad.v`

The development source was copied from `../ascon-rtl` at source HEAD `361f628` if
that repository was available.

Why this matters:

- local development can use `../ascon-rtl`;
- external hardening/submission flows should not depend on sibling directories;
- `info.yaml/source_files` now lists repo-local RTL files only.

Refresh vendored RTL after intentional core updates:

```sh
make tt10b-refresh-core
```

Validate packageability:

```sh
make tt10-flow-preflight
make tt10b-package-check
```
