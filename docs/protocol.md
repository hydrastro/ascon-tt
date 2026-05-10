# Tiny Tapeout ASCON byte protocol

The design uses the standard Tiny Tapeout port shape and implements a simple byte-command protocol.

## Production defaults

| Parameter | Default |
|---|---:|
| `ENABLE_PERM_DEBUG` | 0 |
| `ENABLE_DIAGNOSTICS` | 0 |
| `ENABLE_OUT_BUFFER` | 0 |
| `MAX_AD_BYTES` | 32 |
| `MAX_DATA_BYTES` | 32 |

## Essential AEAD commands

| Command | Value | Payload | Response | Notes |
|---|---:|---:|---:|---|
| `CMD_NOP` | `0x00` | 0 | none | no operation |
| `CMD_SET_MODE` | `0x01` | 1 | ack | `0` encrypt, `1` decrypt |
| `CMD_SET_AD_BYTES` | `0x02` | 4 | ack | little-endian byte count |
| `CMD_SET_MSG_BYTES` | `0x03` | 4 | ack | little-endian byte count |
| `CMD_LOAD_KEY` | `0x10` | 16 | ack | key bytes |
| `CMD_LOAD_NONCE` | `0x11` | 16 | ack | nonce bytes |
| `CMD_LOAD_AD` | `0x12` | AD length | ack | bounded by `MAX_AD_BYTES` |
| `CMD_LOAD_DATA` | `0x13` | message length | ack | plaintext for enc, ciphertext for dec |
| `CMD_LOAD_TAG` | `0x14` | 16 | ack | decrypt expected tag |
| `CMD_START` | `0x20` | 0 | ack/error | starts AEAD job |
| `CMD_STATUS` | `0x21` | 0 | status byte | busy/done/auth status |
| `CMD_READ_OUT_BYTE` | `0x30` | 1 index | byte/error | reads ciphertext/plaintext byte |
| `CMD_READ_RESULT_TAG` | `0x31` | 1 index | byte/error | reads encryption tag byte |
| `CMD_CLEAR` | `0x40` | 0 | ack | clears frontend state |

## Disabled production debug paths

The production default disables standalone permutation debug and diagnostic readbacks to reduce area. Debug profiles can re-enable them for simulation and development.
