# TT-14D — Shared AEAD core

This adds the first real min-area RTL candidate:

```text
src/ascon_tt_aead_shared.v
```

It preserves the current dual-core implementation as:

```text
src/ascon_tt_aead_bridge_dual.v
```

and turns `src/ascon_tt_aead_bridge.v` into a selector:

```verilog
USE_SHARED_AEAD = 0  // current known-good dual enc/dec reference
USE_SHARED_AEAD = 1  // new shared single-permutation AEAD core
```

The shared core keeps the same bridge-facing interface so the serial frontend
does not need to change. Internally it uses:

- one `ascon_perm_unrolled`;
- one 320-bit ASCON state register;
- one AEAD FSM for both encrypt and decrypt modes;
- the same constants, padding, domain separation, and internal word order as the
  existing `ascon-rtl` enc/dec cores.

## Test

```sh
make sim-aead-vectors-shared-prod-directout
make synth-prod-aead-shared-directout
```

If vectors fail, keep production on `USE_SHARED_AEAD=0` and debug the shared core
against the old bridge.

## Area intent

This is the architectural cut that should remove the simultaneous encrypt-core
and decrypt-core duplication. If this is still too large after hardening, the
next extreme step belongs in `ascon-rtl`: an even smaller serial/bit-sliced
permutation implementation.

