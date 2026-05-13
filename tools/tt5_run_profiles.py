#!/usr/bin/env python3
"""Run Yosys synthesis for all 4 ASCON profiles and save output to build/tt5/.

Usage: python3 tools/tt5_run_profiles.py [--src-dir src] [--out-dir build/tt5]
"""
from __future__ import annotations
import argparse, subprocess, sys, textwrap
from pathlib import Path

SRC_FILES = [
    "src/project.v",
    "src/ascon_tt_serial_frontend.v",
    "src/ascon_tt_aead_core_stub.v",
    "src/ascon_tt_perm_core.v",
    "src/ascon_tt_aead_bridge.v",
    "src/ascon_tt_aead_bridge_dual.v",
    "src/ascon_tt_aead_shared.v",
    "src/ascon_core/ascon_round_comb.v",
    "src/ascon_core/ascon_perm_unrolled.v",
    "src/ascon_core/ascon_aead128_enc_ad.v",
    "src/ascon_core/ascon_aead128_dec_ad.v",
]
TOP = "tt_um_ascon_aead"
PROFILES = [(0,1), (0,8), (1,1), (1,8)]

def run_one(variant: int, rpc: int, out_dir: Path, repo_root: Path) -> Path:
    src = " ".join(str(repo_root / f) for f in SRC_FILES)
    script = textwrap.dedent(f"""
        read_verilog {src}
        chparam -set ASCON_VARIANT {variant} -set ROUNDS_PER_CYCLE {rpc} {TOP}
        chparam -set USE_SHARED_AEAD 1 {TOP}
        synth -top {TOP}
        check
        stat
    """).strip()
    out = out_dir / f"v{variant}_r{rpc}.txt"
    print(f"  Synthesising ASCON_VARIANT={variant} ROUNDS_PER_CYCLE={rpc} ...", flush=True)
    result = subprocess.run(
        ["yosys", "-p", script],
        capture_output=True, text=True
    )
    combined = result.stdout + ("\n" + result.stderr if result.stderr else "")
    out.write_text(combined)
    ok = result.returncode == 0
    print(f"  -> {out} ({'ok' if ok else 'FAILED rc=' + str(result.returncode)})")
    return out

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--out-dir", default="build/tt5")
    args = p.parse_args()
    repo_root = Path(__file__).parent.parent
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    for v, r in PROFILES:
        run_one(v, r, out_dir, repo_root)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
