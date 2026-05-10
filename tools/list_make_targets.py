#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

mk = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("Makefile")
text = mk.read_text(errors="replace").splitlines()

section = "General"
targets: list[tuple[str, str, int]] = []
for i, line in enumerate(text, 1):
    msec = re.match(r"#\s*-{5,}\s*$", line)
    # Section titles in this Makefile are between dashed comment lines. Accept any all-caps-ish comment.
    if line.startswith("# ") and not set(line.strip()) <= {"#", "-"}:
        title = line[2:].strip()
        if title and not title.startswith("SPDX"):
            section = title
    mt = re.match(r"^([A-Za-z0-9_.-]+):(?:\s|$)", line)
    if mt:
        name = mt.group(1)
        if not name.startswith("$(") and name not in {".PHONY"}:
            targets.append((name, section, i))

print("| target | section | line |")
print("|---|---|---:|")
for name, sec, line in targets:
    print(f"| `{name}` | {sec} | {line} |")
