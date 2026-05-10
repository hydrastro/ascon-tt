# TT-5 — Synthesis profile matrix

This phase adds synthesis profiles so area can be measured before changing the
working full-AEAD Tiny Tapeout RTL.

Profiles:

- `full_debug`: current TT top, including frontend, AEAD bridge, enc, dec, and permutation debug path
- `full_aead_bridge`: AEAD bridge plus enc/dec cores, without TT frontend/debug permutation wrapper
- `enc_only`: encryption+AD core
- `dec_only`: decryption+AD core
- `perm_debug`: TT permutation debug wrapper
- `perm_core`: raw permutation core
