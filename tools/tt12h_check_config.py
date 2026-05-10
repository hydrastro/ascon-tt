#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

cfg = Path("src/config.json")
if not cfg.exists():
    print("[FAIL] missing src/config.json")
    sys.exit(1)

try:
    data = json.loads(cfg.read_text())
except Exception as e:
    print(f"[FAIL] src/config.json is not valid JSON: {e}")
    sys.exit(1)

required = [
    "CLOCK_PORT",
    "CLOCK_PERIOD",
    "PL_TARGET_DENSITY_PCT",
    "RUN_CTS",
    "FP_SIZING",
]
missing = [k for k in required if k not in data]
if missing:
    print("[FAIL] src/config.json missing keys: " + ", ".join(missing))
    sys.exit(1)

if data["CLOCK_PORT"] != "clk":
    print("[FAIL] CLOCK_PORT should be clk")
    sys.exit(1)

print("[OK] src/config.json present and basic keys valid")
