# TT-6 — Full-AEAD top without permutation debug

TT-6 keeps the default Tiny Tapeout top as the debug-capable build, but adds an
`ENABLE_PERM_DEBUG` parameter.

- `ENABLE_PERM_DEBUG=1`: current debug build with standalone permutation oracle
- `ENABLE_PERM_DEBUG=0`: full-AEAD build with standalone permutation core removed

The no-perm build is the first realistic full-AEAD tapeout candidate. It keeps
encryption, decryption, AD handling, tag generation, and tag verification. It
does not remove the real AEAD permutation cores inside the ASCON encrypt/decrypt
engines.

Useful commands:

```sh
make sim-aead-vectors-noperm
make synth-full-aead-top
make tt6-report
```
