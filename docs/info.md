# ASCON AEAD Serial Accelerator

This project targets a full Ascon-AEAD128 accelerator behind a Tiny Tapeout-style
8-bit serial command/data protocol.

Current status:

- TT-1 scaffold
- Tiny Tapeout top-level ports
- serial command frontend skeleton
- placeholder AEAD core stub

The final goal is full AEAD:

- encryption
- decryption
- associated data
- partial final blocks
- tag generation
- tag verification

The final design should reuse verified logic from `ascon-rtl`, but it must not
use AXI, MMIO, NEORV32, XBUS, or large FIFOs.
