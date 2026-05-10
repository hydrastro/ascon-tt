# TT-14B — Shared-core extraction checkpoint

Before writing the single-datapath AEAD core, extract the exact implementation
facts from the current known-good RTL:

- bridge interface;
- encrypt/decrypt module ports;
- permutation handshake;
- constants and localparams;
- case/FSM structure;
- byte/block/tag/auth handling.

Run:

```sh
make tt14b-extract-shared-core-inputs
```

Output:

```text
build/tt14b/shared_core_inputs.md
```

Paste that report before the shared-core patch. The shared core must preserve the
current frontend protocol and vector behavior while replacing the dual enc/dec
implementation with one permutation/datapath.
