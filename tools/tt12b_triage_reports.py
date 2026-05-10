#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

if len(sys.argv) < 2:
    print("usage: tt12b_triage_reports.py <run-dir> [out.md]", file=sys.stderr)
    raise SystemExit(2)

run_dir = Path(sys.argv[1]).resolve()
out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("build/tt12b/triage.md")
out_path.parent.mkdir(parents=True, exist_ok=True)

if not run_dir.exists():
    print(f"ERROR: run dir does not exist: {run_dir}", file=sys.stderr)
    raise SystemExit(1)

text_files: list[Path] = []
for p in run_dir.rglob("*"):
    if not p.is_file():
        continue
    if p.suffix.lower() in {".log", ".rpt", ".txt", ".json", ".yaml", ".yml", ".tcl"} or p.name in {"metrics.json", "metadata.json"}:
        text_files.append(p)

patterns = [
    ("fatal", re.compile(r"\b(fatal|failed|failure)\b", re.I)),
    ("error", re.compile(r"\berror\b", re.I)),
    ("warning", re.compile(r"\bwarning\b", re.I)),
    ("drc", re.compile(r"\b(drc|violation|violations)\b", re.I)),
    ("lvs", re.compile(r"\b(lvs|netgen|mismatch|short|open)\b", re.I)),
    ("antenna", re.compile(r"\bantenna\b", re.I)),
    ("timing", re.compile(r"\b(setup|hold|wns|tns|slack|violated|violation)\b", re.I)),
    ("unconnected", re.compile(r"\b(unconnected|undriven|multi-driven|multiple drivers|combinational loop)\b", re.I)),
]

counts = {name: 0 for name, _ in patterns}
hits: list[tuple[str, str, int, str]] = []

for p in text_files:
    try:
        lines = p.read_text(errors="replace").splitlines()
    except Exception:
        continue
    rel = str(p.relative_to(run_dir))
    for i, line in enumerate(lines, 1):
        compact = line.strip()
        if not compact:
            continue
        for name, pat in patterns:
            if pat.search(compact):
                counts[name] += 1
                if len(hits) < 400:
                    hits.append((name, rel, i, compact[:240]))

metrics: list[tuple[str, object]] = []
for name in ["metrics.json", "metadata.json"]:
    for p in run_dir.rglob(name):
        try:
            obj = json.loads(p.read_text(errors="replace"))
        except Exception:
            continue
        # Flatten a few likely useful metrics.
        def walk(prefix: str, value: object) -> None:
            if isinstance(value, dict):
                for k, v in value.items():
                    walk(f"{prefix}.{k}" if prefix else str(k), v)
            elif isinstance(value, (int, float, str, bool)) and len(metrics) < 120:
                key = prefix.lower()
                if any(word in key for word in [
                    "area", "cell", "util", "wire", "drc", "lvs", "antenna", "wns", "tns",
                    "slack", "viol", "gds", "die", "core", "route", "power"
                ]):
                    metrics.append((prefix, value))
        walk("", obj)

md: list[str] = []
md.append("# TT-12B hardening report triage")
md.append("")
md.append(f"Run directory: `{run_dir}`")
md.append("")
md.append("## Signal counts")
md.append("")
md.append("| category | hits |")
md.append("|---|---:|")
for name in counts:
    md.append(f"| {name} | {counts[name]} |")
md.append("")
if metrics:
    md.append("## Selected metrics")
    md.append("")
    md.append("| metric | value |")
    md.append("|---|---:|")
    for k, v in metrics:
        md.append(f"| `{k}` | `{v}` |")
    md.append("")
md.append("## First matched report lines")
md.append("")
if hits:
    md.append("| category | file | line | text |")
    md.append("|---|---|---:|---|")
    for name, rel, line, txt in hits:
        txt = txt.replace("|", "\\|")
        md.append(f"| {name} | `{rel}` | {line} | {txt} |")
else:
    md.append("No matched warning/error/DRC/LVS/timing lines found by the heuristic scanner.")
md.append("")

out_path.write_text("\n".join(md))
print(out_path)

# Nonzero only for strong failure categories.
if counts["fatal"] or counts["error"]:
    raise SystemExit(1)
raise SystemExit(0)
