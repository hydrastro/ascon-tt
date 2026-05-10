# TT-8 force frontend parameter pass-through

This patch fixes the production-default transition by rewriting the
`u_frontend` instance to pass every top-level profile parameter explicitly:

- `ENABLE_PERM_DEBUG`
- `ENABLE_DIAGNOSTICS`
- `ENABLE_OUT_BUFFER`
- `MAX_AD_BYTES`
- `MAX_DATA_BYTES`

The Tiny Tapeout top defaults remain production-oriented. The frontend module
local defaults remain debug-friendly for direct developer use.

The Makefile debug simulations pass explicit debug parameters to the TT top.
Production synthesis remains the default `make synth` behavior.

The lint command also disables two known production-default warnings categories
for this profile transition:

- unused perm-debug registers after the debug generate block is disabled;
- width expansion on disabled constant assignments.
