# TT-7A.3 — Production buffer-size area matrix

TT-7A.3 exposes the Tiny Tapeout top-level buffer bounds:

- `MAX_AD_BYTES`
- `MAX_DATA_BYTES`

The frontend already uses these parameters internally. This phase passes them
through the top-level `tt_um_ascon_aead` module so production area can be
measured for different bounded-message profiles.

The default remains unchanged:

- `MAX_AD_BYTES=32`
- `MAX_DATA_BYTES=32`

Useful commands:

```sh
make tt7a3-buffer-matrix
make tt7a3-report
```

Profiles measured:

- AD=8, message=8
- AD=16, message=16
- AD=32, message=32
- AD=8, message=32
- AD=32, message=8

This does not change the default functionality. It only adds synthesis profiles
so we can decide whether smaller Tiny Tapeout buffer bounds are worth offering.
