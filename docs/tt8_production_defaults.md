# TT-8 — Production defaults

TT-8 promotes the direct-output full-AEAD profile to the default Tiny Tapeout
top-level configuration.

Default `tt_um_ascon_aead` parameters:

- `ENABLE_PERM_DEBUG=0`
- `ENABLE_DIAGNOSTICS=0`
- `ENABLE_OUT_BUFFER=0`
- `MAX_AD_BYTES=32`
- `MAX_DATA_BYTES=32`

This matters because the Tiny Tapeout flow normally synthesizes the top-level
module with its default parameter values. Before TT-8, the default build could
still be the larger debug-oriented configuration unless the Makefile supplied
explicit `chparam` overrides.

Debug behavior is preserved through explicit Makefile simulation parameters:

```sh
make debug-regression
```

Production/default check:

```sh
make prod-default-check
make prod-default-report
```

The expected default synthesis profile should be close to the previously measured
`prod_aead_top_directout` profile.
