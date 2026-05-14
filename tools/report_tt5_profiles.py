#!/usr/bin/env python3
"""Parse Yosys synthesis logs and print a profile comparison table.

Usage: python3 tools/report_tt5_profiles.py build/tt5/v*.txt [--debug]
"""
from __future__ import annotations
import re, sys
from pathlib import Path


def parse_log(path: Path, debug: bool = False) -> dict[str, object]:
    text = path.read_text(errors="replace")

    total_cells = -1
    primitive_counts: dict[str, int] = {}

    # Find stat section — starts at last "=== <something> ===" heading before
    # "Number of cells:" or before "$_" lines.
    # Yosys stat output looks like:
    #
    #   === module_name ===
    #      Number of wires: ...
    #      Number of cells: 1234
    #        1234 $_AND_
    #         567 $_DFF_P_
    #      ...
    #   === design hierarchy ===
    #      module_name   1
    #   ...
    #   Printing statistics.
    #   Number of cells: 1234    ← summary line (may appear at end)

    # Method 1: look for primitive cell lines directly
    # Pattern: optional leading whitespace, integer count, space, $_NAME_
    prim_pattern = re.compile(r"^\s*(\d+)\s+(\$_[A-Za-z0-9_]+)\s*$", re.MULTILINE)
    for m in prim_pattern.finditer(text):
        name = m.group(2)
        count = int(m.group(1))
        # Take max in case the same cell appears in multiple stat blocks
        primitive_counts[name] = max(primitive_counts.get(name, 0), count)

    if primitive_counts:
        total_cells = sum(primitive_counts.values())

    # Method 2: "Number of cells: N" (stat summary line)
    m = re.search(r"Number of cells:\s+(\d+)", text)
    if m:
        n = int(m.group(1))
        # Use the larger of primitive sum or the stated total
        total_cells = max(total_cells, n)

    # Method 3: last integer on a line alone in the stat block
    if total_cells < 0:
        marks = list(re.finditer(r"=== design hierarchy ===", text))
        if marks:
            tail = text[marks[-1].end():]
            m = re.search(r"^\s*(\d+)\s+\S+\s*$", tail, flags=re.M)
            if m:
                total_cells = int(m.group(1))

    # check ran cleanly
    checks_ok = "Found and reported 0 problems." in text

    # warnings
    m = re.search(r"Warnings:\s+(\d+)\s+unique messages?,\s+(\d+)\s+total", text)
    warnings = int(m.group(2)) if m else len(re.findall(r"^Warning:", text, flags=re.M))

    # DFF: all registered cell flavours
    dff_total = sum(v for k, v in primitive_counts.items()
                    if re.match(r"\$_(S?DFF|DFFE|SDFFE|ADFF)", k))

    if debug:
        print(f"\n[DEBUG] {path.name}: cells={total_cells} dff={dff_total} "
              f"primitives={sorted(primitive_counts.items())}", file=sys.stderr)

    return {
        "profile":  path.stem,
        "cells":    total_cells,
        "dff":      dff_total,
        "mux":      primitive_counts.get("$_MUX_", 0),
        "xor":      primitive_counts.get("$_XOR_", 0),
        "xnor":     primitive_counts.get("$_XNOR_", 0),
        "and":      primitive_counts.get("$_AND_", 0),
        "andnot":   primitive_counts.get("$_ANDNOT_", 0),
        "or":       primitive_counts.get("$_OR_", 0),
        "warnings": warnings,
        "check0":   "yes" if checks_ok else "NO",
    }


def main(argv: list[str]) -> int:
    debug = "--debug" in argv
    paths = [Path(x) for x in argv[1:] if not x.startswith("-") and Path(x).exists()]
    if not paths:
        print("usage: report_tt5_profiles.py build/tt5/v*.txt [--debug]",
              file=sys.stderr)
        return 2

    rows = [parse_log(p, debug) for p in paths]
    rows.sort(key=lambda r: str(r["profile"]))

    cols = ["profile", "cells", "dff", "mux", "xor", "xnor",
            "and", "andnot", "or", "warnings", "check0"]
    widths = {c: max(len(c), *(len(str(r[c])) for r in rows)) for c in cols}

    print("  ".join(c.ljust(widths[c]) for c in cols))
    print("  ".join("-" * widths[c] for c in cols))
    for r in rows:
        print("  ".join(str(r[c]).ljust(widths[c]) for c in cols))

    if any(r["cells"] < 0 for r in rows):
        print("\nWARNING: some profiles have cells=-1 (Yosys parse failed).",
              file=sys.stderr)
        print("Try:  python3 tools/report_tt5_profiles.py build/tt5/v*.txt --debug",
              file=sys.stderr)
        print("Or:   head -100 build/tt5/v1_r1.txt", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
