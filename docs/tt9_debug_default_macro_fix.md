# TT-9 debug-default macro fix

The production top-level defaults remain the normal defaults used by `make synth`
and by external Tiny Tapeout-style flows.

Debug simulations now also compile `src/project.v` with:

```sh
-DTT_DEBUG_DEFAULTS
```

This makes the top-level defaults debug-oriented at preprocessing time, so the
old permutation/diagnostic regression tests do not depend on simulator-specific
`-P` parameter override behavior.

Normal synthesis does not define `TT_DEBUG_DEFAULTS`, so the production defaults
remain:

- `ENABLE_PERM_DEBUG=0`
- `ENABLE_DIAGNOSTICS=0`
- `ENABLE_OUT_BUFFER=0`
- `MAX_AD_BYTES=32`
- `MAX_DATA_BYTES=32`
