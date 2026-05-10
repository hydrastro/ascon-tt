# TT-14C — Shared AEAD core schedule

This is the intended shared-datapath ASCON-AEAD128 flow. It is a design guide
for the min-area implementation; the current dual-core bridge remains the
reference oracle.

## External interface

The shared core should initially match the current bridge-level interface:

```text
clk
rst_n
clear_i
start_i
decrypt_i
key_i[127:0]
nonce_i[127:0]
ad_bytes_i[31:0]
msg_bytes_i[31:0]
tag_i[127:0]
ad_block0_i[127:0]
ad_block1_i[127:0]
data_block0_i[127:0]
data_block1_i[127:0]
busy_o
done_o
auth_ok_o
result_tag_o[127:0]
out_block0_o[127:0]
out_block1_o[127:0]
```

That lets the serial frontend remain unchanged while replacing the internals.

## Datapath

Use:

- `state_q[319:0]`
- `key_q[127:0]`
- counters for AD/message block index
- one `ascon_perm_unrolled`
- small muxing around `state_q`

Do **not** instantiate both current `ascon_aead128_enc_ad` and
`ascon_aead128_dec_ad`.

## FSM skeleton

Suggested high-level states:

```text
IDLE
INIT_LOAD
INIT_P12_START
INIT_P12_WAIT
INIT_KEY_XOR
AD_ABSORB
AD_P6_START
AD_P6_WAIT
DOMAIN_SEP
MSG_PROCESS
MSG_P6_START
MSG_P6_WAIT
FINAL_KEY_XOR
FINAL_P12_START
FINAL_P12_WAIT
TAG_OUTPUT
DONE
```

Decrypt mode differs in message processing and final authentication:

```text
encrypt: ciphertext = plaintext XOR state_slice
decrypt: plaintext  = ciphertext XOR state_slice
decrypt: absorb ciphertext into state
decrypt: compare computed tag against tag_i
```

## Minimum-area assumptions

- Process at most the current bounded TT frontend sizes.
- Reuse the same permutation hardware for p12 and p6.
- Avoid large duplicate output buffers when direct-output mode is enabled.
- Prefer sequential FSM work over parallel datapath duplication.

## Verification rule

The shared core is not valid until it passes the same AEAD vector tests as the
reference bridge.
