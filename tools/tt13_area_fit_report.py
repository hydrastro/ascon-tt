#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

def read_logs(paths: list[str]) -> str:
    chunks: list[str] = []
    if paths:
        for s in paths:
            p = Path(s)
            if p.is_file():
                chunks.append(p.read_text(errors="replace"))
            elif p.is_dir():
                for f in p.rglob("*"):
                    if f.is_file() and f.suffix.lower() in {".log", ".txt", ".rpt"}:
                        chunks.append(f.read_text(errors="replace"))
    else:
        for root in [Path("runs"), Path("build")]:
            if root.exists():
                for f in root.rglob("*"):
                    if f.is_file() and f.suffix.lower() in {".log", ".txt", ".rpt"}:
                        chunks.append(f.read_text(errors="replace"))
    return "\n".join(chunks)

def last_float(pattern: str, text: str) -> float | None:
    vals = re.findall(pattern, text)
    if not vals:
        return None
    return float(vals[-1].replace(",", ""))

text = read_logs(sys.argv[1:])

region = last_float(r"Region area:\s*([0-9.]+)\s*um\^2", text)
fixed = last_float(r"Fixed instances area:\s*([0-9.]+)\s*um\^2", text)
movable = last_float(r"Movable instances area:\s*([0-9.]+)\s*um\^2", text)
util = last_float(r"Utilization:\s*([0-9.]+)\s*%", text)
std = last_float(r"Standard cells area:\s*([0-9.]+)\s*um\^2", text)

print("# TT-13 area fit report")
print()

if region is None or movable is None:
    print("No OpenROAD global-placement area lines found.")
    print("Pass a log path explicitly, for example:")
    print()
    print("```sh")
    print("python3 tools/tt13_area_fit_report.py runs/wokwi")
    print("```")
    raise SystemExit(1)

fixed = fixed or 0.0
total = fixed + movable
util_calc = 100.0 * total / region

print("| metric | value |")
print("|---|---:|")
print(f"| placement region area | {region:,.3f} µm² |")
print(f"| fixed instances area | {fixed:,.3f} µm² |")
print(f"| movable/stdcell area | {movable:,.3f} µm² |")
if std is not None:
    print(f"| standard cells area reported | {std:,.3f} µm² |")
if util is not None:
    print(f"| utilization reported | {util:.3f}% |")
print(f"| utilization recomputed | {util_calc:.3f}% |")
print()

print("## Required movable-cell reduction")
print()
print("| target total utilization | max movable area | required movable reduction | reduction % |")
print("|---:|---:|---:|---:|")
for target in [1.00, 0.95, 0.90, 0.85, 0.80, 0.70, 0.60]:
    max_movable = region * target - fixed
    reduction = max(0.0, movable - max_movable)
    reduction_pct = 100.0 * reduction / movable if movable else 0.0
    print(f"| {100*target:.0f}% | {max_movable:,.3f} µm² | {reduction:,.3f} µm² | {reduction_pct:.2f}% |")

print()
print("## Interpretation")
print()
if util_calc >= 100.0:
    print("- This is an absolute area failure: standard cells plus fixed instances exceed the placement region.")
    print("- Increasing placement density cannot fix a utilization above 100%.")
else:
    print("- This is below 100%; placement/routing tuning may be relevant.")
print("- For routability, target materially below 100%, not merely 99%.")
print("- If this is already an 8x2 Tiny Tapeout macro, the architectural area must be reduced or the design must move to a larger/non-TT target.")
