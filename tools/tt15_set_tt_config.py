#!/usr/bin/env python3
"""
tt15_set_tt_config.py — update src/config.json + info.yaml for a given
tile size, clock frequency, ASCON variant, and rounds-per-cycle.

Usage:
  python3 tools/tt15_set_tt_config.py \
    --tiles 6x2 --clock-hz 10000000 \
    --variant 1 --rpc 1
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--tiles',    default='6x2')
    p.add_argument('--clock-hz', type=int, default=10_000_000)
    p.add_argument('--variant',  type=int, default=1, choices=[0, 1])
    p.add_argument('--rpc',      type=int, default=1)
    p.add_argument('--pdk',      default='sky130A', choices=['sky130A', 'gf180mcuD'])
    args = p.parse_args()

    root = Path(__file__).parent.parent
    cfg_path  = root / 'src' / 'config.json'
    info_path = root / 'info.yaml'

    clock_period_ns = round(1e9 / args.clock_hz, 3)

    # ── src/config.json ──────────────────────────────────────────────────────
    cfg = json.loads(cfg_path.read_text())

    cfg['CLOCK_PERIOD'] = clock_period_ns

    # Update FP_DEF_TEMPLATE for tile size and PDK
    cfg['FP_DEF_TEMPLATE'] = (
        f"dir::../tt/tech/{args.pdk}/def/tt_block_{args.tiles}_pg.def"
    )

    # Update VERILOG_DEFINES so yosys can parse project.v correctly
    cfg['VERILOG_DEFINES'] = [
        f"USE_SHARED_AEAD=1",
        f"ASCON_VARIANT={args.variant}",
        f"ROUNDS_PER_CYCLE={args.rpc}",
        "ENABLE_OUT_BUFFER=0",
        "ENABLE_DIAGNOSTICS=0",
        "ENABLE_PERM_DEBUG=0",
    ]

    cfg_path.write_text(json.dumps(cfg, indent=2))
    print(f"[tt15] config.json: CLOCK_PERIOD={clock_period_ns} ns  "
          f"tiles={args.tiles}  ASCON_VARIANT={args.variant}  RPC={args.rpc}")

    # ── info.yaml ─────────────────────────────────────────────────────────────
    try:
        import yaml
        info = yaml.safe_load(info_path.read_text())
        info['project']['tiles']    = args.tiles
        info['project']['clock_hz'] = args.clock_hz
        info_path.write_text(yaml.dump(info, default_flow_style=False))
        print(f"[tt15] info.yaml: tiles={args.tiles}  clock_hz={args.clock_hz}")
    except ImportError:
        # pyyaml not available in nix shell — patch with regex instead
        text = info_path.read_text()
        text = re.sub(r"(tiles:\s*)\S+",  f"\\g<1>\"{args.tiles}\"",  text)
        text = re.sub(r"(clock_hz:\s*)\d+", f"\\g<1>{args.clock_hz}", text)
        info_path.write_text(text)
        print(f"[tt15] info.yaml: tiles={args.tiles}  clock_hz={args.clock_hz} (regex)")

    # ── src/user_config.json ───────────────────────────────────────────────────
    # tt_tool.py reads this to get VERILOG_DEFINES for the harden run.
    # Generate it now so --create-user-config just uses this directly.
    user_cfg = {
        "ASCON_VARIANT":    args.variant,
        "ROUNDS_PER_CYCLE": args.rpc,
        "USE_SHARED_AEAD":  1,
        "ENABLE_PERM_DEBUG":    0,
        "ENABLE_DIAGNOSTICS":   0,
        "ENABLE_OUT_BUFFER":    0,
        "MAX_AD_BYTES":   32,
        "MAX_DATA_BYTES": 32,
    }
    ucfg_path = root / 'src' / 'user_config.json'
    ucfg_path.write_text(json.dumps(user_cfg, indent=2))
    print(f"[tt15] user_config.json written")

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
