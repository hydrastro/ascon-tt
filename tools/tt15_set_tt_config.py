#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

VALID_TILES = {"1x1", "1x2", "2x2", "3x2", "4x2", "6x2", "8x2"}

def update_yaml_scalar(text: str, key: str, value: str) -> str:
    # Updates the first non-comment scalar line matching "key:".
    # Good enough for info.yaml where project.tiles and project.clock_hz are
    # unique in this repo.
    rx = re.compile(rf"^(\s*{re.escape(key)}\s*:\s*).*$", re.M)
    if rx.search(text):
        return rx.sub(rf"\g<1>{value}", text, count=1)
    return text

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tiles", required=True)
    ap.add_argument("--clock-hz", type=int, required=True)
    ap.add_argument("--info", default="info.yaml")
    ap.add_argument("--config", default="src/config.json")
    args = ap.parse_args()

    if args.tiles not in VALID_TILES:
        raise SystemExit(f"ERROR: invalid tiles '{args.tiles}'. Valid: {', '.join(sorted(VALID_TILES))}")
    if args.clock_hz <= 0:
        raise SystemExit("ERROR: clock-hz must be positive")

    info_path = Path(args.info)
    text = info_path.read_text()
    text = update_yaml_scalar(text, "tiles", f'"{args.tiles}"')
    text = update_yaml_scalar(text, "clock_hz", str(args.clock_hz))
    info_path.write_text(text)

    cfg_path = Path(args.config)
    if cfg_path.exists():
        try:
            cfg = json.loads(cfg_path.read_text())
        except Exception:
            cfg = {}

        period_ns = 1e9 / float(args.clock_hz)
        for key in list(cfg.keys()):
            if key in {"CLOCK_PERIOD", "CLOCK_PERIOD_NS"}:
                cfg[key] = period_ns

        meta = cfg.setdefault("_ascon_tt_sweep", {})
        meta["tiles"] = args.tiles
        meta["clock_hz"] = int(args.clock_hz)
        meta["clock_period_ns"] = period_ns
        cfg_path.write_text(json.dumps(cfg, indent=2) + "\n")

    print(f"set tiles={args.tiles} clock_hz={args.clock_hz}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
