#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from pathlib import Path

def load(path: str) -> dict:
    return json.loads(Path(path).read_text())

if len(sys.argv) != 3:
    print("usage: tt12a_compare_manifests.py <old-manifest.json> <new-manifest.json>", file=sys.stderr)
    raise SystemExit(2)

a = load(sys.argv[1])
b = load(sys.argv[2])

fa = {f["path"]: f for f in a.get("files", [])}
fb = {f["path"]: f for f in b.get("files", [])}

added = sorted(set(fb) - set(fa))
removed = sorted(set(fa) - set(fb))
changed = sorted(k for k in set(fa) & set(fb) if fa[k].get("sha256") != fb[k].get("sha256"))

print(f"old: {sys.argv[1]}")
print(f"new: {sys.argv[2]}")
print()
print(f"added:   {len(added)}")
print(f"removed: {len(removed)}")
print(f"changed: {len(changed)}")

def show(title: str, rows: list[str]) -> None:
    if not rows:
        return
    print()
    print(title)
    for r in rows[:80]:
        print(f"  {r}")
    if len(rows) > 80:
        print(f"  ... {len(rows) - 80} more")

show("ADDED", added)
show("REMOVED", removed)
show("CHANGED", changed)
