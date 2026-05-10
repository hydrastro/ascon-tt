# Minimum-area complete ASCON AEAD128 plan

## Is complete ASCON AEAD128 possible?

Yes, but not with the current dual full-core architecture inside the selected
Tiny Tapeout area.

The current design reached hardening and failed at global placement because the
standard cells exceeded the placement region. The measured report required:

| target | movable-area reduction needed |
|---:|---:|
| 100% utilization | 6.89% |
| 90% utilization | 16.39% |
| 80% utilization | 25.89% |

A realistic implementation should target at least the 90% case, preferably
closer to 80%.

## Why the current architecture is too large

`src/ascon_tt_aead_bridge.v` instantiates both:

- `ascon_aead128_enc_ad`
- `ascon_aead128_dec_ad`

Each of those contains its own AEAD control/datapath structure. This is
convenient and good as a reference, but it is not the minimum-area ASIC shape.

## Minimum-area architecture

Use one shared datapath:

```text
serial frontend
    |
    v
job registers / small buffers
    |
    v
single AEAD FSM
    |
    v
one 320-bit state register + one ascon_perm_unrolled
```

Production path requirements:

- exactly one ASCON permutation instance;
- one shared 320-bit state;
- one encrypt/decrypt mode bit;
- common initialization, AD absorption, message processing, and finalization;
- decrypt compares computed tag against loaded tag;
- existing frontend command protocol preserved.

## Bring-up strategy

1. Keep `ascon_tt_aead_bridge.v` as the known-good reference.
2. Add `src/ascon_tt_aead_shared.v`.
3. Add a parameter such as `USE_SHARED_AEAD`.
4. Simulate both implementations against the same vector test.
5. Only switch production default to shared after vector parity passes.
6. Re-run synthesis profile and hardening.

## Success criteria

Functional:

```sh
make sim-aead-vectors-prod-directout
make lint
make synth
```

Area:

```sh
make tt5-profiles
make tt13-area-report
```

Physical:

```sh
make tt12-create-user-config
make tt12-harden
make tt12b-after-harden
```

Goal: hardening reaches at least placement with utilization materially under
100%; under 90% is the first credible target.
