#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

roots = [Path(p) for p in sys.argv[1:]] if len(sys.argv) > 1 else [Path("runs"), Path("build")]
candidates: list[tuple[float, Path]] = []

interesting_suffixes = {
    ".gds", ".def", ".lef", ".spef", ".sdf", ".rpt", ".log", ".json", ".mag", ".spice"
}
interesting_names = {"metrics.json", "metadata.json"}

for root in roots:
    if not root.exists():
        continue
    for d in root.rglob("*"):
        if not d.is_dir():
            continue
        try:
            files = [p for p in d.rglob("*") if p.is_file()]
        except OSError:
            continue
        if not files:
            continue
        if any(p.suffix.lower() in interesting_suffixes or p.name in interesting_names for p in files):
            newest = max(p.stat().st_mtime for p in files)
            candidates.append((newest, d))

if not candidates:
    print("")
    raise SystemExit(1)

# Prefer a directory that looks like the upper run directory rather than a deep reports subdir.
candidates.sort(reverse=True, key=lambda x: x[0])
best = candidates[0][1]

for _, d in candidates[:50]:
    parts = d.parts
    if "runs" in parts and any((d / name).exists() for name in ["reports", "logs", "final", "objects"]):
        best = d
        break

print(best)
