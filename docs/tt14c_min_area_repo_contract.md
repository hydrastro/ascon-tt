# TT-14C — Min-area repo contract

Branch name:

```sh
git checkout -b min-area
```

## Goal

Implement complete ASCON-AEAD128 in the smallest practical Tiny Tapeout area
without detaching the TT repo from the reusable `ascon-rtl` library.

## Boundary

### `ascon-rtl` owns reusable cryptographic RTL

Keep these generic and reusable:

- ASCON round function;
- ASCON permutation;
- ASCON constants and byte/word ordering helpers if promoted;
- generic AEAD reference cores;
- algorithm/vector verification infrastructure.

### `ascon-tt` owns Tiny Tapeout integration

Keep these TT-specific:

- `tt_um_ascon_aead` top module;
- `ui_in`, `uo_out`, `uio_*`, `ena`, `clk`, `rst_n`;
- serial byte command protocol;
- TT diagnostics/debug commands;
- hardening config and layout artifacts;
- area profile matrix.

## What min-area means

The current full-AEAD bridge is a functional reference, but it instantiates both
encrypt and decrypt engines. That is not minimum area.

The min-area production path should instantiate:

- one 320-bit ASCON state register;
- one `ascon_perm_unrolled` from `ascon-rtl`;
- one AEAD FSM handling both encrypt and decrypt modes;
- only the buffers required by the existing serial frontend.

## Do not rewrite the wheel

Do not reimplement `ascon_round_comb` or `ascon_perm_unrolled` in `ascon-tt`.

Initial shared-core development can happen in `ascon-tt` because the frontend,
I/O, and hardening constraints are TT-specific. Once the shared AEAD core is
stable and generic enough, promote it back into `ascon-rtl` as a reusable module.

## Promotion rule

A module belongs in `ascon-rtl` if it has a generic hardware interface and no TT
pins/protocol assumptions.

A module belongs in `ascon-tt` if it mentions or structurally assumes:

- `ui_in`;
- `uo_out`;
- `uio_in`;
- `uio_out`;
- `uio_oe`;
- Tiny Tapeout command/status bytes;
- Tiny Tapeout hardening profiles.

## Implementation sequence

1. Keep `src/ascon_tt_aead_bridge.v` as the reference implementation.
2. Add `src/ascon_tt_aead_shared.v`.
3. Reuse `src/ascon_core/ascon_perm_unrolled.v`.
4. Add a compile-time selector only after the shared module compiles.
5. Run the same vector tests against the current bridge and the shared core.
6. Compare synthesis area.
7. Switch production default only after vector parity and area improvement.
8. Consider upstreaming the generic shared core to `ascon-rtl`.
