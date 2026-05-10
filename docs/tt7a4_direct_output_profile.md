# TT-7A.4 — Direct-output production profile

This phase adds `ENABLE_OUT_BUFFER`.

Defaults remain unchanged:

- `ENABLE_OUT_BUFFER=1`

The experimental production profile uses:

- `ENABLE_PERM_DEBUG=0`
- `ENABLE_DIAGNOSTICS=0`
- `ENABLE_OUT_BUFFER=0`

When output buffering is disabled, output bytes are read directly from the AEAD
bridge output blocks rather than from `out_mem_q`.

This is intentionally a profile first. If `sim-aead-vectors-prod-directout`
passes, the AEAD bridge output is stable enough for the current serial protocol
between completion and result readback.

Useful commands:

```sh
make sim-aead-vectors-prod-directout
make synth-prod-aead-top-directout
make tt7a4-report
```
