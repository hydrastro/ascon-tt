# ASCON Tiny Tapeout architecture

## Goal

Implement full Ascon-AEAD128 on Tiny Tapeout using a small byte-serial interface.

## Non-goals

The TT implementation must not include:

- AXI
- MMIO32
- NEORV32/XBUS
- 128-bit external data bus
- large FIFOs

## Top-level interface

The Tiny Tapeout top exposes the standard HDL user-module ports:

```verilog
module tt_um_ascon_aead (
  input  wire [7:0] ui_in,
  output wire [7:0] uo_out,
  input  wire [7:0] uio_in,
  output wire [7:0] uio_out,
  output wire [7:0] uio_oe,
  input  wire       ena,
  input  wire       clk,
  input  wire       rst_n
);
```

## Serial protocol

Dedicated input bus:

```text
ui_in[7:0] = command/data byte
```

Dedicated output bus:

```text
uo_out[7:0] = response/data byte
```

Bidirectional control pins:

```text
uio_in[0]  = in_valid
uio_out[0] = in_ready

uio_in[1]  = out_ready
uio_out[1] = out_valid

uio_out[2] = busy
uio_out[3] = done
uio_out[4] = auth_ok
uio_out[5] = error

uio_out[7:6] reserved
```

`uio_oe = 8'b0011_1111`, so the design drives `uio_out[5:0]`.

## Command map

```text
0x00 NOP
0x01 SET_MODE          next byte: 0=encrypt, 1=decrypt
0x02 SET_AD_BYTES      next 4 bytes, little-endian
0x03 SET_MSG_BYTES     next 4 bytes, little-endian

0x10 LOAD_KEY          next 16 bytes
0x11 LOAD_NONCE        next 16 bytes
0x12 LOAD_AD           next ad_bytes bytes
0x13 LOAD_DATA         next msg_bytes bytes
0x14 LOAD_TAG          next 16 bytes, decrypt only

0x20 START             full AEAD start, currently stubbed
0x21 STATUS

0x40 CLEAR

0x50 READ_MODE
0x51 READ_AD_COUNT_LOW
0x52 READ_DATA_COUNT_LOW
0x53 READ_KEY_XOR
0x54 READ_NONCE_XOR
0x55 READ_TAG_XOR
0x56 READ_AD_XOR
0x57 READ_DATA_XOR

0x60 LOAD_STATE        next 40 bytes, permutation debug/integration path
0x61 SET_ROUNDS        next byte: 6, 8, or 12
0x62 START_PERM
0x63 READ_STATE_XOR
0x64 READ_STATE_BYTE   next byte: index 0..39
```

## Current TT-3 status

Implemented:

- command parser
- mode register
- AD/message length registers
- key/nonce/tag loading
- AD/data byte counting
- XOR debug checksums
- permutation state loading
- RPC=1 permutation start/done
- permutation state byte/XOR readback

Still stubbed:

- `START` full AEAD execution
- output ciphertext/plaintext queue
- tag readout from full AEAD

## Implementation plan

1. TT-1: project scaffold and protocol skeleton.
2. TT-2: byte-storage frontend and command parser.
3. TT-3: permutation integration using one RPC=1 engine.
4. TT-4: shared full-AEAD FSM using the integrated permutation engine.
5. TT-5: test against `ascon-rtl` vectors.
6. TT-6: OpenLane/Tiny Tapeout area/frequency loop.
