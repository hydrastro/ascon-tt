# TT-7A — Slim no-perm frontend profile

TT-7A keeps the default debug-capable Tiny Tapeout build unchanged, but makes the
`ENABLE_PERM_DEBUG=0` production profile more aggressively constant-fold the
standalone permutation debug path.

The patch guards the standalone permutation command handlers:

- `CMD_LOAD_STATE`
- `CMD_SET_ROUNDS`
- `CMD_START_PERM`
- `CMD_READ_STATE_XOR`
- `CMD_READ_STATE_BYTE`

When `ENABLE_PERM_DEBUG=0`, those commands return an error response and do not
drive the permutation debug state machinery. Full AEAD commands are unchanged.

Useful commands:

```sh
make clean && make sanity
make sim-aead-vectors-noperm
make synth-full-aead-top
make tt6-report
```
