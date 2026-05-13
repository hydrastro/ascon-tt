#!/usr/bin/env python3
"""
tt15_set_tt_config.py — update src/config.json and info.yaml for a given
tile size, clock frequency, ASCON variant, and rounds-per-cycle, then
write src/user_config.json with the correct Verilog defines.

Usage:
  python3 tools/tt15_set_tt_config.py \
    --tiles 6x2 --clock-hz 10000000 \
    --variant 1 --rpc 1
"""
from __future__ import annotations
import argparse, json, sys, re
from pathlib import Path


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument('--tiles',    default='6x2',     help='Tile size e.g. 6x2')
    p.add_argument('--clock-hz', type=int, default=10_000_000)
    p.add_argument('--variant',  type=int, default=1, choices=[0, 1],
                   help='0=ASCON-128, 1=ASCON-128a')
    p.add_argument('--rpc',      type=int, default=1,
                   help='ROUNDS_PER_CYCLE: 1=min-area, 8=max-perf')
    args = p.parse_args()

    root = Path(__file__).parent.parent
    cfg_path  = root / 'src' / 'config.json'
    info_path = root / 'info.yaml'

    # ── src/config.json ──────────────────────────────────────────────────
    cfg = json.loads(cfg_path.read_text())

    clock_period_ns = round(1e9 / args.clock_hz, 3)
    cfg['CLOCK_PERIOD'] = clock_period_ns

    # Tile size → FP_DEF_TEMPLATE
    if 'FP_DEF_TEMPLATE' in cfg:
        cfg['FP_DEF_TEMPLATE'] = re.sub(
            r'tt_block_\d+x\d+_', f'tt_block_{args.tiles}_', cfg['FP_DEF_TEMPLATE']
        )

    cfg_path.write_text(json.dumps(cfg, indent=2))
    print(f"[tt15] config.json: CLOCK_PERIOD={clock_period_ns} ns  tiles={args.tiles}")

    # ── info.yaml ────────────────────────────────────────────────────────
    try:
        import yaml
        info = yaml.safe_load(info_path.read_text())
        info['project']['tiles']    = args.tiles
        info['project']['clock_hz'] = args.clock_hz
        info_path.write_text(yaml.dump(info, default_flow_style=False))
        print(f"[tt15] info.yaml: tiles={args.tiles}  clock_hz={args.clock_hz}")
    except ImportError:
        print("[tt15] WARNING: pyyaml not available; info.yaml not updated")

    # ── src/user_config.json (Verilog defines) ───────────────────────────
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
    print(f"[tt15] user_config.json: ASCON_VARIANT={args.variant}  RPC={args.rpc}")

    return 0


if __name__ == '__main__':
    raise SystemExit(main())
