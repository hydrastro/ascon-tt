#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from dataclasses import dataclass

@dataclass
class Scenario:
    name: str
    movable_um2: float
    fixed_um2: float
    region_um2: float

    @property
    def total_um2(self) -> float:
        return self.movable_um2 + self.fixed_um2

    @property
    def util_pct(self) -> float:
        return 100.0 * self.total_um2 / self.region_um2

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--region", type=float, default=302420.045)
    ap.add_argument("--fixed", type=float, default=6112.112)
    ap.add_argument("--current-movable", type=float, default=318224.483)
    ap.add_argument("--out-json", default="build/tt14/area_model.json")
    args = ap.parse_args()

    # These are intentionally simple models based on observed Yosys cell profiles.
    # They are not a replacement for hardening, but they keep the direction honest.
    scenarios = [
        Scenario("current_dual_full_aead", args.current_movable, args.fixed, args.region),
        Scenario("minus_7_percent_barely_100", args.current_movable * 0.9311, args.fixed, args.region),
        Scenario("minus_16_percent_target_90", args.current_movable * 0.8361, args.fixed, args.region),
        Scenario("minus_26_percent_target_80", args.current_movable * 0.7411, args.fixed, args.region),
        Scenario("single_datapath_goal_25_percent_cut", args.current_movable * 0.75, args.fixed, args.region),
        Scenario("single_datapath_stretch_35_percent_cut", args.current_movable * 0.65, args.fixed, args.region),
    ]

    print("# TT-14 area model")
    print()
    print("| scenario | movable area | total area | utilization | verdict |")
    print("|---|---:|---:|---:|---|")

    data = []
    for s in scenarios:
        if s.util_pct >= 100.0:
            verdict = "does not fit"
        elif s.util_pct >= 90.0:
            verdict = "fits area, risky for route"
        elif s.util_pct >= 80.0:
            verdict = "reasonable first target"
        else:
            verdict = "good margin"
        print(f"| {s.name} | {s.movable_um2:,.3f} µm² | {s.total_um2:,.3f} µm² | {s.util_pct:.2f}% | {verdict} |")
        data.append({
            "name": s.name,
            "movable_um2": s.movable_um2,
            "fixed_um2": s.fixed_um2,
            "region_um2": s.region_um2,
            "total_um2": s.total_um2,
            "util_pct": s.util_pct,
            "verdict": verdict,
        })

    from pathlib import Path
    out = Path(args.out_json)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2) + "\n")

    print()
    print("## Decision")
    print()
    print("The current dual full-AEAD architecture is not an area-fit candidate.")
    print("A real TT full-AEAD attempt needs a shared single ASCON permutation/datapath.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
