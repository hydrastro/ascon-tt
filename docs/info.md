# ASCON AEAD Serial Accelerator

This Tiny Tapeout project implements a byte-serial ASCON AEAD accelerator targeting the GF26a shuttle.  The external interface uses the standard Tiny Tapeout input/output pins as a compact command and response bus.  The internal production datapath uses one shared ASCON permutation engine and one AEAD control FSM to support ASCON-128a and ASCON-128 configurations without instantiating separate encrypt and decrypt cores in the normal production path.

The command protocol loads the key, nonce, associated-data length, message length, associated data, plaintext/ciphertext, and optional decrypt tag.  After a start command, the circuit returns output bytes and the computed authentication tag.  Status pins report ready/valid, busy, done, authentication result, and error conditions.

The intended GF26a hardening configuration is ASCON-128a, 4x4 tiles, 10 MHz, one permutation round per cycle, and production debug disabled.
