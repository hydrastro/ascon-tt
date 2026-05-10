# TT-4A — Bounded job buffers and result readback

TT-4A adds the storage layer required before replacing the AEAD `START` stub
with the real cryptographic FSM.

## Added behavior

The serial frontend now stores:

- key, 16 bytes
- nonce, 16 bytes
- expected decrypt tag, 16 bytes
- associated data, up to 32 bytes
- payload/ciphertext input, up to 32 bytes
- output data, up to 32 bytes
- result tag, 16 bytes

## New readback commands

```text
0x30 READ_OUT_BYTE       next byte: output index
0x31 READ_RESULT_TAG     next byte: tag index
0x58 READ_OUT_XOR
0x59 READ_RESULT_TAG_XOR
```

## Current algorithm behavior

`START` is still a stub. It validates required inputs and fills:

```text
out[i] = data[i] XOR 0x5a
result_tag[i] = key_xor XOR nonce_xor XOR tag_xor XOR ad_xor XOR data_xor XOR i
```

This is intentionally not cryptographic. It exists only to prove the byte
storage and result-readback protocol before the full AEAD FSM is connected.

## Bounds

The first full-AEAD bring-up target is bounded:

```text
AD bytes   <= 32
DATA bytes <= 32
```

The protocol can later be converted to true streaming if needed.
