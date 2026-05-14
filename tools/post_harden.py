#!/usr/bin/env python3
"""
post_harden.py — show stats and find GDS after a librelane run.

Usage:
  python3 tools/post_harden.py [run_dir]
  
Default run_dir: runs/wokwi
"""
import sys, re, glob, os
from pathlib import Path


def find_latest_run(run_dir: Path) -> Path:
    """Find the most recent timestamped run subdirectory."""
    # librelane creates: runs/wokwi/<timestamp>/
    # or runs/wokwi/ itself may be the run root
    candidates = sorted(run_dir.glob("*/"), key=lambda p: p.stat().st_mtime, reverse=True)
    if candidates:
        return candidates[0]
    return run_dir


def find_files(root: Path, pattern: str):
    return sorted(root.rglob(pattern), key=lambda p: p.stat().st_mtime)


def show_stats(run_dir: Path):
    run_dir = Path(run_dir)
    if not run_dir.exists():
        print(f"ERROR: {run_dir} does not exist. Run make tt12-harden first.")
        sys.exit(1)

    # Find the actual run root (may be nested)
    latest = find_latest_run(run_dir)
    print(f"Run directory: {latest}")
    print()

    # ── GDS ──────────────────────────────────────────────────────────────────
    gds_files = find_files(run_dir, "*.gds") + find_files(run_dir, "*.gds.gz")
    print("GDS files:")
    if gds_files:
        for g in gds_files:
            size = g.stat().st_size
            print(f"  {g}  ({size/1024:.0f} KB)")
    else:
        print("  (none found)")
    print()

    # ── Area / utilization ────────────────────────────────────────────────────
    area_patterns = ["*area*", "*utilization*", "*stat*", "*metrics*"]
    area_files = []
    for pat in area_patterns:
        area_files += find_files(run_dir, f"**/{pat}.rpt")
        area_files += find_files(run_dir, f"**/{pat}.log")
        area_files += find_files(run_dir, f"**/{pat}.json")
    area_files = list(dict.fromkeys(area_files))  # dedup preserving order

    print("Area / utilization:")
    shown = False
    for f in area_files[-3:]:  # show most recent 3
        text = f.read_text(errors="replace")
        # Look for key numbers
        for line in text.splitlines():
            if any(kw in line.lower() for kw in
                   ["total area", "util", "utilization", "cell count",
                    "number of cells", "design area"]):
                print(f"  [{f.name}] {line.strip()}")
                shown = True
    if not shown:
        # Try metrics.json (librelane standard output)
        metrics = find_files(run_dir, "metrics.json")
        if metrics:
            import json
            try:
                m = json.loads(metrics[-1].read_text())
                for k in ["design__instance__count", "design__die__bbox",
                          "design__core__area", "utilization"]:
                    if k in m:
                        print(f"  {k}: {m[k]}")
                        shown = True
            except Exception:
                pass
    if not shown:
        print("  (no area data found)")
    print()

    # ── Timing ───────────────────────────────────────────────────────────────
    print("Timing:")
    timing_shown = False
    # Check metrics.json first
    metrics = find_files(run_dir, "metrics.json")
    if metrics:
        import json
        try:
            m = json.loads(metrics[-1].read_text())
            for k in ["timing__setup__ws", "timing__hold__ws",
                      "timing__setup__tns", "timing__hold__tns",
                      "clock__period"]:
                if k in m:
                    print(f"  {k}: {m[k]}")
                    timing_shown = True
        except Exception:
            pass
    
    if not timing_shown:
        # Search timing reports
        for f in find_files(run_dir, "*timing*")[-2:]:
            text = f.read_text(errors="replace")
            for line in text.splitlines():
                if any(kw in line.lower() for kw in ["wns", "tns", "slack", "met"]):
                    print(f"  [{f.name}] {line.strip()}")
                    timing_shown = True
    if not timing_shown:
        print("  (no timing data found)")
    print()

    # ── Violations ────────────────────────────────────────────────────────────
    print("DRC / violations:")
    viol_shown = False
    metrics = find_files(run_dir, "metrics.json")
    if metrics:
        import json
        try:
            m = json.loads(metrics[-1].read_text())
            for k in ["magic__drc__error__count", "klayout__drc__error__count",
                      "design__violations"]:
                if k in m:
                    v = m[k]
                    ok = "✓" if v == 0 else "✗"
                    print(f"  {ok} {k}: {v}")
                    viol_shown = True
        except Exception:
            pass
    if not viol_shown:
        print("  (run with make tt12-harden to populate)")
    print()


if __name__ == "__main__":
    run_dir = sys.argv[1] if len(sys.argv) > 1 else "runs/wokwi"
    show_stats(Path(run_dir))
