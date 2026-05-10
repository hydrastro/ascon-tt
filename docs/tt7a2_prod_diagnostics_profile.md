# TT-7A.2 — Production diagnostics-off profile

This phase adds `ENABLE_DIAGNOSTICS`.

Defaults remain debug-friendly:

- `ENABLE_PERM_DEBUG=1`
- `ENABLE_DIAGNOSTICS=1`

The production full-AEAD profile uses:

- `ENABLE_PERM_DEBUG=0`
- `ENABLE_DIAGNOSTICS=0`

This keeps the essential AEAD byte protocol but disables diagnostic readbacks:

- mode readback
- AD/data count readback
- key/nonce/tag XOR summaries
- AD/data/output/result-tag XOR summaries

Essential operations remain enabled:

- set mode
- set AD/message lengths
- load key/nonce/AD/data/tag
- start
- status
- read output byte
- read result tag byte

Commands:

```sh
make sim-aead-vectors-prod
make synth-prod-aead-top
make tt7a2-report
```
