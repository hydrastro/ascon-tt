# TT-10 — Physical-flow readiness

TT-10 prepares the project for the Tiny Tapeout hardening/GDS stage.

The key point is packaging: external hardening flows will only see files in the
submitted repository, plus whatever the template explicitly supports. A local
`../ascon-rtl` path is convenient for development but unsafe for submission
unless the core RTL is vendored or otherwise included in the repository layout
used by the hardening flow.

## Current required core RTL

The Tiny Tapeout project depends on these ASCON core files:

- `ascon_round_comb.v`
- `ascon_perm_unrolled.v`
- `ascon_aead128_enc_ad.v`
- `ascon_aead128_dec_ad.v`

The TT flow preflight checks that these files exist inside the submission repo
and that `info.yaml` lists only paths that exist inside the repo.

## Commands

Run:

```sh
make tt10-flow-preflight
```

Full local release gate:

```sh
make tt10-release-check
```

## Physical-design sequence

Once TT-10 is green, the next major stage is physical implementation:

1. clone or adapt the official Tiny Tapeout HDL template;
2. make sure `info.yaml` has the right `top_module` and `source_files`;
3. run the local hardening flow;
4. inspect synthesis, placement, routing, DRC/LVS/antenna/timing reports;
5. inspect generated GDS in KLayout/Magic only after the hardening run is clean.

Do not optimize `config.tcl` casually. Tiny Tapeout’s defaults are chosen for the
process and shuttle constraints.
