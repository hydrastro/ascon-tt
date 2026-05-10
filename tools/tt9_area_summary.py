#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

def parse_cells(path: Path) -> dict[str, int | str]:
    text = path.read_text(errors="replace")
    matches = list(re.finditer(r"^\s*(\d+)\s+cells\s*$", text, flags=re.M))
    cells = int(matches[-1].group(1)) if matches else -1
    m = re.search(r"Warnings:\s+(\d+)\s+unique messages?,\s+(\d+)\s+total", text)
    warnings = int(m.group(2)) if m else len(re.findall(r"^Warning:", text, flags=re.M))
    check0 = "yes" if "Found and reported 0 problems." in text else "?"
    return {"profile": path.stem, "cells": cells, "warnings": warnings, "check0": check0}

files = [Path(p) for p in sys.argv[1:]] or sorted(Path("build").glob("**/*.txt"))
rows = [parse_cells(p) for p in files if p.is_file()]

print("| profile | cells | warnings | check0 |")
print("|---|---:|---:|:---:|")
for r in sorted(rows, key=lambda x: str(x["profile"])):
    cells_s = "" if r["cells"] == -1 else str(r["cells"])
    print(f"| {r['profile']} | {cells_s} | {r['warnings']} | {r['check0']} |")
