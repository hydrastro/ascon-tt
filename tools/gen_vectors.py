#!/usr/bin/env python3
"""
gen_vectors.py — generate sim/generated/ascon_aead128_ad_vectors.vh

Usage:
  python3 tools/gen_vectors.py [--variant 128|128a] [output_path]

Default: ASCON-128a, output to sim/generated/ascon_aead128_ad_vectors.vh

The .vh file is included INSIDE a Verilog module body (localparam, not `define).
Bus encoding matches ascon_tt_serial_frontend.v extract_byte128_5():
  byte i at bits[64+8*i]  for i < 8
  byte i at bits[8*(i-8)] for i >= 8
"""
from __future__ import annotations
import argparse, sys
from pathlib import Path

# ── Reference implementations ────────────────────────────────────────────────

def _ror64(x: int, n: int) -> int:
    return ((x >> n) | (x << (64 - n))) & 0xFFFF_FFFF_FFFF_FFFF

def _perm(S: tuple, rounds: int) -> tuple:
    RC = [0xf0,0xe1,0xd2,0xc3,0xb4,0xa5,0x96,0x87,0x78,0x69,0x5a,0x4b]
    x0, x1, x2, x3, x4 = S
    M = (1 << 64) - 1
    for r in range(12 - rounds, 12):
        x2 ^= RC[r]
        a0=(x0^x4)&M; a1=x1; a2=(x2^x1)&M; a3=x3; a4=(x4^x3)&M
        t0=(a0^(~a1&a2))&M; t1=(a1^(~a2&a3))&M; t2=(a2^(~a3&a4))&M
        t3=(a3^(~a4&a0))&M; t4=(a4^(~a0&a1))&M
        s0=(t0^t4)&M; s1=(t1^t0)&M; s2=t2; s3=(t3^t2)&M; s4=t4
        x0=(s0^_ror64(s0,19)^_ror64(s0,28))&M
        x1=(s1^_ror64(s1,61)^_ror64(s1,39))&M
        x2=(~(s2^_ror64(s2, 1)^_ror64(s2, 6)))&M
        x3=(s3^_ror64(s3,10)^_ror64(s3,17))&M
        x4=(s4^_ror64(s4, 7)^_ror64(s4,41))&M
    return (x0, x1, x2, x3, x4)

def _le(b: bytes) -> int:
    """Little-endian bytes → 64-bit int (byte 0 at bits[7:0])."""
    return int.from_bytes(b.ljust(8, b'\x00')[:8], 'little')

def _st(x: int, n: int) -> bytes:
    return x.to_bytes(8, 'little')[:n]

def _mask(n: int) -> int:
    return (1 << (8 * n)) - 1 if n < 8 else 0xFFFF_FFFF_FFFF_FFFF

def _pad(n: int) -> int:
    """0x01 at byte position n in a 64-bit little-endian word."""
    return 1 << (8 * n)

# Domain separator: verified against ascon_aead128_enc_ad.v → 0x8000000000000000
DSEP = 0x8000_0000_0000_0000


def encrypt_128a(key: bytes, nonce: bytes, ad: bytes, msg: bytes) -> tuple[bytes, bytes]:
    """ASCON-128a: IV=0x00001000808c0001, rate=16B, PA=12, PB=8."""
    IV = 0x0000_1000_808c_0001
    k0, k1 = _le(key[:8]), _le(key[8:])
    S = (IV, k0, k1, _le(nonce[:8]), _le(nonce[8:]))
    S = _perm(S, 12)
    S = (S[0], S[1], S[2], S[3] ^ k0, S[4] ^ k1)

    a = ad
    if a:
        while len(a) >= 16:
            S = _perm((S[0] ^ _le(a[:8]), S[1] ^ _le(a[8:16]), S[2], S[3], S[4]), 8)
            a = a[16:]
        # tail (always present when ad non-empty, even if 0 bytes after full blocks)
        t = a
        if len(t) <= 8:
            S = (S[0] ^ (_le(t) & _mask(len(t))) ^ _pad(len(t)), S[1], S[2], S[3], S[4])
        else:
            n1 = len(t) - 8
            S = (S[0] ^ _le(t[:8]),
                 S[1] ^ (_le(t[8:]) & _mask(n1)) ^ _pad(n1),
                 S[2], S[3], S[4])
        S = _perm(S, 8)
    S = (S[0], S[1], S[2], S[3], S[4] ^ DSEP)

    m = msg
    ct = bytearray()
    while len(m) >= 16:
        c0, c1 = S[0] ^ _le(m[:8]), S[1] ^ _le(m[8:16])
        ct += _st(c0, 8) + _st(c1, 8)
        S = _perm((c0, c1, S[2], S[3], S[4]), 8)
        m = m[16:]
    # tail
    if len(m) == 0:
        S = (S[0] ^ 1, S[1], S[2], S[3], S[4])
    elif len(m) <= 8:
        ct += _st((S[0] ^ _le(m)) & _mask(len(m)), len(m))
        S = (S[0] ^ (_le(m) & _mask(len(m))) ^ _pad(len(m)), S[1], S[2], S[3], S[4])
    else:
        n1 = len(m) - 8
        c0 = S[0] ^ _le(m[:8])
        ct += _st(c0, 8) + _st((S[1] ^ _le(m[8:])) & _mask(n1), n1)
        S = (c0, S[1] ^ (_le(m[8:]) & _mask(n1)) ^ _pad(n1), S[2], S[3], S[4])

    S = _perm((S[0], S[1], S[2] ^ k0, S[3] ^ k1, S[4]), 12)
    tag = _st(S[3] ^ k0, 8) + _st(S[4] ^ k1, 8)
    return bytes(ct), bytes(tag)


def encrypt_128(key: bytes, nonce: bytes, ad: bytes, msg: bytes) -> tuple[bytes, bytes]:
    """ASCON-128: IV=0x80400c0600000000, rate=8B, PA=12, PB=6."""
    IV = 0x8040_0c06_0000_0000
    k0, k1 = _le(key[:8]), _le(key[8:])
    S = (IV, k0, k1, _le(nonce[:8]), _le(nonce[8:]))
    S = _perm(S, 12)
    S = (S[0], S[1], S[2], S[3] ^ k0, S[4] ^ k1)

    a = ad
    if a:
        while len(a) >= 8:
            S = _perm((S[0] ^ _le(a[:8]), S[1], S[2], S[3], S[4]), 6)
            a = a[8:]
        t = a
        S = (S[0] ^ (_le(t) & _mask(len(t))) ^ _pad(len(t)), S[1], S[2], S[3], S[4])
        S = _perm(S, 6)
    S = (S[0], S[1], S[2], S[3], S[4] ^ DSEP)

    m = msg
    ct = bytearray()
    while len(m) >= 8:
        c0 = S[0] ^ _le(m[:8])
        ct += _st(c0, 8)
        S = _perm((c0, S[1], S[2], S[3], S[4]), 6)
        m = m[8:]
    if len(m) == 0:
        S = (S[0] ^ 1, S[1], S[2], S[3], S[4])
    else:
        ct += _st((S[0] ^ _le(m)) & _mask(len(m)), len(m))
        S = (S[0] ^ (_le(m) & _mask(len(m))) ^ _pad(len(m)), S[1], S[2], S[3], S[4])

    S = _perm((S[0], S[1], S[2] ^ k0, S[3] ^ k1, S[4]), 12)
    tag = _st(S[3] ^ k0, 8) + _st(S[4] ^ k1, 8)
    return bytes(ct), bytes(tag)


# ── Bus encoding ─────────────────────────────────────────────────────────────

def bus128(b16: bytes) -> str:
    """
    Pack 16 bytes into the 128-bit bus value used by extract_byte128_5() in
    ascon_tt_serial_frontend.v:
      byte i at bits[64 + 8*i]  for i < 8   (upper 64 bits)
      byte i at bits[8*(i-8)]   for i >= 8  (lower 64 bits)
    """
    val = 0
    for i in range(8):
        val |= int(b16[i]) << (64 + 8 * i)
    for i in range(8, 16):
        val |= int(b16[i]) << (8 * (i - 8))
    return f"{val:032x}"


# ── Known-good test vectors ──────────────────────────────────────────────────

KEY   = bytes(range(16))
NONCE = bytes(range(16))
AD    = bytes(range(32))
MSG   = bytes(range(32))

KNOWN = {
    '128a': {
        'ct':  '4c086d27a3b51a2333cfc7f22172a9bcad88b8d4d77e50622d788345fa7bee44',
        'tag': '68915d3f9422289f2349d6a3b4160397',
    },
    '128': {
        'ct':  'f39231445a358b1fdbd4b2ba2b82e156f49b618cde2b117200dec29c451079c7',
        'tag': '327278656ef93042b52bec41cf5c9f8e',
    },
}


def generate_vh(out: Path, variant: str) -> None:
    encrypt = encrypt_128a if variant == '128a' else encrypt_128
    ct, tag = encrypt(KEY, NONCE, AD, MSG)

    # Self-check against known good
    known = KNOWN[variant]
    assert ct.hex()  == known['ct'],  f"CT mismatch for {variant}!\n  got {ct.hex()}\n  exp {known['ct']}"
    assert tag.hex() == known['tag'], f"Tag mismatch for {variant}!\n  got {tag.hex()}\n  exp {known['tag']}"

    ad0, ad1 = AD[:16], AD[16:]
    pt0, pt1 = MSG[:16], MSG[16:]
    ct0, ct1 = ct[:16], ct[16:]

    lines = [
        f"// Auto-generated by tools/gen_vectors.py --variant {variant}",
        "// Do NOT edit by hand.  Include INSIDE a Verilog module body.",
        f"// ASCON-{variant}: key=nonce=0x00..0x0f  ad=msg=0x00..0x1f",
        "//",
        f"// ct:  {ct.hex()}",
        f"// tag: {tag.hex()}",
        "//",
        "// Bus encoding: byte i at bits[64+8*i] (i<8) or bits[8*(i-8)] (i>=8).",
        "",
        f"localparam [127:0] VEC_AEAD_AD_KEY          = 128'h{bus128(KEY)};",
        f"localparam [127:0] VEC_AEAD_AD_NONCE        = 128'h{bus128(NONCE)};",
        f"localparam integer VEC_AEAD_AD_C7_AD_BYTES  = 32;",
        f"localparam integer VEC_AEAD_AD_C7_MSG_BYTES = 32;",
        f"localparam [127:0] VEC_AEAD_AD_C7_AD0       = 128'h{bus128(ad0)};",
        f"localparam [127:0] VEC_AEAD_AD_C7_AD1       = 128'h{bus128(ad1)};",
        f"localparam [127:0] VEC_AEAD_AD_C7_PT0       = 128'h{bus128(pt0)};",
        f"localparam [127:0] VEC_AEAD_AD_C7_PT1       = 128'h{bus128(pt1)};",
        f"localparam [127:0] VEC_AEAD_AD_C7_CT0       = 128'h{bus128(ct0)};",
        f"localparam [127:0] VEC_AEAD_AD_C7_CT1       = 128'h{bus128(ct1)};",
        f"localparam [127:0] VEC_AEAD_AD_C7_TAG       = 128'h{bus128(tag)};",
        "",
    ]
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines))
    print(f"[gen_vectors] {out}  variant={variant}  ct={ct.hex()[:16]}...  tag={tag.hex()}")


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--variant', choices=['128', '128a'], default='128a',
                   help='ASCON variant (default: 128a)')
    p.add_argument('output', nargs='?',
                   default='sim/generated/ascon_aead128_ad_vectors.vh',
                   help='Output .vh file path')
    args = p.parse_args()
    generate_vh(Path(args.output), args.variant)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
