# TT-7A.5 — Direct-output buffer-size matrix

TT-7A.5 measures buffer-bound variants after enabling the direct-output
production profile.

Production settings:

- `ENABLE_PERM_DEBUG=0`
- `ENABLE_DIAGNOSTICS=0`
- `ENABLE_OUT_BUFFER=0`

Profiles measured:

- AD=8, message=8
- AD=16, message=16
- AD=32, message=32
- AD=8, message=32
- AD=32, message=8

Useful commands:

```sh
make tt7a5-directout-buffer-matrix
make tt7a5-report
```

This lets us separate the remaining input-buffer cost from the output-buffer cost
that TT-7A.4 already removed.
