# TT-14 — Single-datapath full AEAD plan

The first physical hardening attempt reached global placement and failed with:

```text
[GPL-0301] Utilization 107.397 % exceeds 100%.
```

Observed fit numbers:

| target total utilization | required movable reduction |
|---:|---:|
| 100% | 6.89% |
| 90% | 16.39% |
| 80% | 25.89% |

A 6.89% cut only makes the design barely legal on cell area. It is not enough
for a credible routable macro. The useful target is at least a 16–26% movable
area reduction.

## Decision

Do not keep trying placement knobs on the current dual-core full-AEAD design.

The current full-AEAD top instantiates both encryption and decryption engines
through the AEAD bridge. That is area-expensive. Tiny Tapeout full AEAD should
instead use one shared ASCON permutation/datapath with an encrypt/decrypt mode
FSM.

## TT-14B implementation direction

Create a new shared core, tentatively:

```text
src/ascon_tt_aead_shared.v
```

It should replace the current bridge internals for production builds.

Required properties:

1. one `ascon_perm_unrolled` instance only;
2. one 320-bit state register;
3. one controller handling:
   - initialization,
   - associated-data absorption,
   - plaintext/ciphertext processing,
   - finalization/tag generation,
   - decrypt authentication check;
4. no simultaneous `ascon_aead128_enc_ad` and `ascon_aead128_dec_ad` instances;
5. same frontend command protocol as the current TT design;
6. same vector tests must pass.

## Keep current architecture as reference

Do not delete the existing dual-core bridge immediately. Keep it as:

- known-good functional reference;
- simulation oracle while bringing up the shared core;
- non-TT/full-size comparison target.

## Success criteria

TT-14B is not complete until all of these pass:

```sh
make sim-aead-vectors-prod-directout
make lint
make synth
make tt5-profiles
make tt12-create-user-config
make tt12-harden
```

Physical success criteria:

- global placement utilization below 100%;
- preferably below 90%;
- no fatal DRC/LVS issues in the post-hardening report triage.
