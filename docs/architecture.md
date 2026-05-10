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

## Proposed serial protocol

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

`uio_oe` is set for the output/status bits driven by the design.

## Initial command map

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

0x20 START
0x21 STATUS
0x30 READ_DATA         emits msg_bytes bytes
0x31 READ_TAG          emits 16 bytes
0x40 CLEAR
```

## Implementation plan

1. TT-1: project scaffold and protocol skeleton.
2. TT-2: byte storage frontend and command parser.
3. TT-3: shared full-AEAD FSM using one RPC=1 permutation engine.
4. TT-4: test against `ascon-rtl` vectors.
5. TT-5: OpenLane/Tiny Tapeout area/frequency loop.
