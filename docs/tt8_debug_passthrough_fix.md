# TT-8 debug pass-through and lint fix

This fixes the TT-8 production-default transition.

The TT top-level defaults remain production-oriented:

- `ENABLE_PERM_DEBUG=0`
- `ENABLE_DIAGNOSTICS=0`
- `ENABLE_OUT_BUFFER=0`
- `MAX_AD_BYTES=32`
- `MAX_DATA_BYTES=32`

The frontend module-local defaults are debug-friendly, but `project.v` explicitly
passes all top-level parameters into `u_frontend`. Therefore:

- the Tiny Tapeout top default still synthesizes the production profile;
- debug simulations can override the TT top with `-P tt_um_ascon_aead...`;
- direct frontend use remains developer-friendly.

The patch also fixes Verilator production-default lint by:

- assigning disabled 8-bit permutation outputs as `8'd0`;
- marking intentionally unused permutation-debug registers/wires in production
  builds as used for lint purposes.
