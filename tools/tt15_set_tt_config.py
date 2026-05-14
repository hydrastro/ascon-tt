#!/usr/bin/env python3
"""Update src/config.json and info.yaml for Tiny Tapeout GF/SKY sizing.

Examples:
  python3 tools/tt15_set_tt_config.py --pdk gf180mcuD --tiles 4x4 --clock-hz 10000000 --variant 1 --rpc 1
  python3 tools/tt15_set_tt_config.py --pdk gf180mcuD --tiles 4x4 --clock-hz 5000000  --variant 0 --rpc 1
"""
from __future__ import annotations
import argparse, json, re, sys
from pathlib import Path

TILES = {
    "gf180mcuD": {
        "suffix": "pgvdd",
        "rt_max_layer": "Metal4",
        "vdd": "VDD",
        "gnd": "VSS",
        "sizes": {
            "1x1": "0 0 346.64 160.72",
            "1x2": "0 0 346.64 325.36",
            "2x2": "0 0 711.20 325.36",
            "3x2": "0 0 1075.76 325.36",
            "3x4": "0 0 1075.76 736.96",
            "4x2": "0 0 1440.32 325.36",
            "4x4": "0 0 1440.32 736.96",
        },
    },
    "sky130A": {
        "suffix": "pg",
        "rt_max_layer": "met4",
        "vdd": "VPWR",
        "gnd": "VGND",
        "sizes": {
            "1x1": "0 0 161.00 111.52",
            "1x2": "0 0 161.00 225.76",
            "2x2": "0 0 334.88 225.76",
            "3x2": "0 0 508.76 225.76",
            "3x4": "0 0 508.76 511.36",
            "4x2": "0 0 682.64 225.76",
            "4x4": "0 0 682.64 511.36",
            "5x4": "0 0 856.52 511.36",
            "6x2": "0 0 1030.40 225.76",
            "6x4": "0 0 1030.40 511.36",
            "8x2": "0 0 1378.16 225.76",
            "8x4": "0 0 1378.16 511.36",
        },
    },
}

def patch_info_yaml(path: Path, tiles: str, clock_hz: int) -> None:
    try:
        import yaml
        info = yaml.safe_load(path.read_text())
        info['project']['tiles'] = tiles
        info['project']['clock_hz'] = clock_hz
        path.write_text(yaml.dump(info, sort_keys=False, default_flow_style=False))
    except Exception:
        text = path.read_text()
        text = re.sub(r'(tiles:\s*)"?[A-Za-z0-9x]+"?', lambda m: f'{m.group(1)}"{tiles}"', text)
        text = re.sub(r'(clock_hz:\s*)[0-9]+', lambda m: f'{m.group(1)}{clock_hz}', text)
        path.write_text(text)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--pdk', default='gf180mcuD', choices=sorted(TILES))
    ap.add_argument('--tiles', default='4x4')
    ap.add_argument('--clock-hz', type=int, default=10_000_000)
    ap.add_argument('--variant', type=int, choices=[0, 1], default=1,
                    help='0=ASCON-128, 1=ASCON-128a')
    ap.add_argument('--rpc', type=int, default=1,
                    help='ROUNDS_PER_CYCLE; use 1 for minimum area')
    args = ap.parse_args()

    tech = TILES[args.pdk]
    if args.tiles not in tech['sizes']:
        print(f"ERROR: {args.pdk} tile size {args.tiles!r} is not available.", file=sys.stderr)
        print(f"Available: {', '.join(tech['sizes'])}", file=sys.stderr)
        return 2

    root = Path(__file__).resolve().parent.parent
    cfg_path = root / 'src' / 'config.json'
    info_path = root / 'info.yaml'
    cfg = json.loads(cfg_path.read_text())

    cfg['CLOCK_PERIOD'] = round(1e9 / args.clock_hz, 3)
    cfg['DIE_AREA'] = tech['sizes'][args.tiles]
    cfg['FP_DEF_TEMPLATE'] = f"dir::../tt/tech/{args.pdk}/def/tt_block_{args.tiles}_{tech['suffix']}.def"
    cfg['VDD_PIN'] = tech['vdd']
    cfg['GND_PIN'] = tech['gnd']
    cfg['RT_MAX_LAYER'] = tech['rt_max_layer']
    cfg['VERILOG_DEFINES'] = [
        'USE_SHARED_AEAD=1',
        f'ASCON_VARIANT={args.variant}',
        f'ROUNDS_PER_CYCLE={args.rpc}',
        'ENABLE_OUT_BUFFER=0',
        'ENABLE_DIAGNOSTICS=0',
        'ENABLE_PERM_DEBUG=0',
    ]

    cfg_path.write_text(json.dumps(cfg, indent=2) + '\n')
    patch_info_yaml(info_path, args.tiles, args.clock_hz)

    print(f"[tt15] pdk={args.pdk} tiles={args.tiles} die_area={cfg['DIE_AREA']}")
    print(f"[tt15] clock={args.clock_hz} Hz period={cfg['CLOCK_PERIOD']} ns")
    print(f"[tt15] ASCON_VARIANT={args.variant} ROUNDS_PER_CYCLE={args.rpc}")
    print(f"[tt15] FP_DEF_TEMPLATE={cfg['FP_DEF_TEMPLATE']}")
    return 0

if __name__ == '__main__':
    raise SystemExit(main())
