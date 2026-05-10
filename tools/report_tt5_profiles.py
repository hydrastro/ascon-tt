#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

def parse_log(path: Path) -> dict[str, object]:
    text = path.read_text(errors="replace")
    marks = list(re.finditer(r"=== design hierarchy ===", text))
    total_cells = -1

    primitive_counts: dict[str, int] = {}
    if marks:
        tail = text[marks[-1].end():]
        m = re.search(r"^\s*(\d+)\s+\S+\s*$", tail, flags=re.M)
        if m:
            total_cells = int(m.group(1))

        for line in tail.splitlines():
            m = re.match(r"\s*(\d+)\s+(\$_[A-Z0-9_]+_?)\s*$", line)
            if m:
                primitive_counts[m.group(2)] = int(m.group(1))

    checks_ok = "Found and reported 0 problems." in text

    m = re.search(r"Warnings:\s+(\d+)\s+unique messages?,\s+(\d+)\s+total", text)
    if m:
        warnings = int(m.group(2))
    else:
        warnings = len(re.findall(r"^Warning:", text, flags=re.M))

    return {
        "profile": path.stem,
        "cells": total_cells,
        "dff": primitive_counts.get("$_DFF_PN0_", 0)
             + primitive_counts.get("$_DFF_PN1_", 0)
             + primitive_counts.get("$_DFFE_PN0P_", 0)
             + primitive_counts.get("$_DFFE_PN1P_", 0),
        "mux": primitive_counts.get("$_MUX_", 0),
        "xor": primitive_counts.get("$_XOR_", 0),
        "xnor": primitive_counts.get("$_XNOR_", 0),
        "and": primitive_counts.get("$_AND_", 0),
        "andnot": primitive_counts.get("$_ANDNOT_", 0),
        "or": primitive_counts.get("$_OR_", 0),
        "warnings": warnings,
        "check0": "yes" if checks_ok else "NO",
    }

def main(argv: list[str]) -> int:
    paths = [Path(x) for x in argv[1:]]
    if not paths:
        print("usage: report_tt5_profiles.py build/tt5/*.txt", file=sys.stderr)
        return 2

    rows = [parse_log(p) for p in paths]
    rows.sort(key=lambda r: str(r["profile"]))

    cols = ["profile", "cells", "dff", "mux", "xor", "xnor", "and", "andnot", "or", "warnings", "check0"]
    widths = {c: max(len(c), *(len(str(r[c])) for r in rows)) for c in cols}

    print("  ".join(c.ljust(widths[c]) for c in cols))
    print("  ".join("-" * widths[c] for c in cols))
    for r in rows:
        print("  ".join(str(r[c]).ljust(widths[c]) for c in cols))

    if any(r["cells"] < 0 or r["check0"] != "yes" for r in rows):
        return 1
    return 0

if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
