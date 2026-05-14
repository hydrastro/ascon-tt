#!/usr/bin/env python3
"""Print throughput/cost estimates from src/config.json."""
import json, math
from pathlib import Path

try:
    cfg = json.loads(Path("src/config.json").read_text())
    clock_hz = round(1e9 / cfg.get("CLOCK_PERIOD", 100))
    defs = {}
    for d in cfg.get("VERILOG_DEFINES", []):
        if "=" in d:
            k, v = d.split("=", 1)
            try: defs[k] = int(v)
            except ValueError: defs[k] = v
        else:
            defs[d] = 1
    variant = defs.get("ASCON_VARIANT", 1)
    rpc     = defs.get("ROUNDS_PER_CYCLE", 1)
    rate    = 16 if variant else 8
    pb      = 8  if variant else 6
    cycles_per_block = math.ceil(pb / rpc)
    throughput_bps   = rate * clock_hz / cycles_per_block
    print(f"  Variant:          ASCON-{'128a' if variant else '128'}")
    print(f"  Clock:            {clock_hz/1e6:.1f} MHz")
    print(f"  Tile:             {cfg.get('_ascon_tt_sweep', {}).get('tiles', '?')} (from config.json sweep field)")
    print(f"  Rate:             {rate} bytes/block")
    print(f"  PB rounds:        {pb}  ({rpc}/cycle  ->  {cycles_per_block} cycles/block)")
    print(f"  Throughput:       {throughput_bps/1e6:.2f} MB/s  ({int(throughput_bps)} bps)")
    print(f"  Init overhead:    12 rounds PA ({math.ceil(12/rpc)} cycles) per operation")
except Exception as e:
    print(f"Error reading config: {e}")
