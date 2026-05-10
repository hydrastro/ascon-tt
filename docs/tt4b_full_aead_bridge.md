# TT-4B — Full AEAD functional bridge

TT-4B replaces the fake `START` behavior with real bounded full-AEAD execution.

The Tiny Tapeout serial frontend now starts a bounded AEAD backend that
instantiates verified `ascon-rtl` cores:

- `ascon_aead128_enc_ad`
- `ascon_aead128_dec_ad`

This gives runtime encrypt/decrypt mode selection and proves that the Tiny
Tapeout byte protocol can run real full AEAD end-to-end.

## Bounds

```text
AD bytes   <= 32
DATA bytes <= 32
```

## Area note

This is a functional proof bridge, not the final area-optimized architecture.
It instantiates both encrypt and decrypt cores. The final Tiny Tapeout design
may need a shared FSM/permutation implementation to reduce area.
