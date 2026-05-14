#!/usr/bin/env python3
from __future__ import annotations

import argparse
import csv
import math
import re
from pathlib import Path

TILE_CHOICES = {
    "1x1": 1,
    "1x2": 2,
    "2x2": 4,
    "3x2": 6,
    "4x2": 8,
    "6x2": 12,
    "8x2": 16,
}

def parse_perf(path: Path):
    rows = []
    rx = re.compile(r"PERF decrypt=(\d+) ad=(\d+) msg=(\d+) cycles=(\d+)")
    for line in path.read_text(errors="replace").splitlines():
        m = rx.search(line)
        if m:
            rows.append({
                "decrypt": int(m.group(1)),
                "ad": int(m.group(2)),
                "msg": int(m.group(3)),
                "cycles": int(m.group(4)),
            })
    return rows

def svg_plot(points, out: Path):
    # points: list of dicts with tiles_count, freq_mhz, cost_eur, throughput_mbps
    if not points:
        out.write_text("<svg xmlns='http://www.w3.org/2000/svg' width='800' height='300'></svg>\n")
        return

    w, h = 1000, 620
    ml, mr, mt, mb = 90, 40, 40, 90
    max_x = max(p["cost_eur"] for p in points) * 1.08
    max_y = max(p["throughput_mbps"] for p in points) * 1.12
    if max_y <= 0: max_y = 1.0

    def x(v): return ml + (w - ml - mr) * v / max_x
    def y(v): return h - mb - (h - mt - mb) * v / max_y

    lines = []
    lines.append(f"<svg xmlns='http://www.w3.org/2000/svg' width='{w}' height='{h}' viewBox='0 0 {w} {h}'>")
    lines.append("<rect width='100%' height='100%' fill='white'/>")
    lines.append(f"<line x1='{ml}' y1='{h-mb}' x2='{w-mr}' y2='{h-mb}' stroke='black'/>")
    lines.append(f"<line x1='{ml}' y1='{mt}' x2='{ml}' y2='{h-mb}' stroke='black'/>")
    lines.append(f"<text x='{w/2}' y='{h-25}' font-size='18' text-anchor='middle'>cost (€) including selected devkit/shipping assumptions</text>")
    lines.append(f"<text x='25' y='{h/2}' font-size='18' text-anchor='middle' transform='rotate(-90 25 {h/2})'>throughput (Mbit/s), payload only</text>")
    lines.append(f"<text x='{w/2}' y='25' font-size='22' text-anchor='middle'>ASCON TT tile/frequency cost-performance model</text>")

    # Grid labels
    for i in range(6):
        xv = max_x * i / 5
        px = x(xv)
        lines.append(f"<line x1='{px:.1f}' y1='{mt}' x2='{px:.1f}' y2='{h-mb}' stroke='#ddd'/>")
        lines.append(f"<text x='{px:.1f}' y='{h-mb+25}' font-size='13' text-anchor='middle'>{xv:.0f}</text>")
    for i in range(6):
        yv = max_y * i / 5
        py = y(yv)
        lines.append(f"<line x1='{ml}' y1='{py:.1f}' x2='{w-mr}' y2='{py:.1f}' stroke='#ddd'/>")
        lines.append(f"<text x='{ml-10}' y='{py+5:.1f}' font-size='13' text-anchor='end'>{yv:.2f}</text>")

    for p in points:
        px, py = x(p["cost_eur"]), y(p["throughput_mbps"])
        label = f'{p["tiles"]} @ {p["freq_mhz"]:.0f}MHz'
        lines.append(f"<circle cx='{px:.1f}' cy='{py:.1f}' r='6' fill='black'/>")
        lines.append(f"<text x='{px+8:.1f}' y='{py-8:.1f}' font-size='12'>{label}</text>")

    lines.append("</svg>")
    out.write_text("\n".join(lines) + "\n")

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--perf-log", default="build/tb_tt16_core_cycles.log")
    ap.add_argument("--out-dir", default="build/tt16")
    ap.add_argument("--freqs", default="5,10,25,50", help="MHz list")
    ap.add_argument("--tiles", default="2x2,3x2,4x2,6x2,8x2")
    ap.add_argument("--tile-price-eur", type=float, default=70.0)
    ap.add_argument("--devkit-eur", type=float, default=300.0)
    ap.add_argument("--shipping-eur", type=float, default=15.0)
    ap.add_argument("--no-devkit", action="store_true")
    args = ap.parse_args()

    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)
    perf_rows = parse_perf(Path(args.perf_log))

    if not perf_rows:
        raise SystemExit(f"ERROR: no PERF rows found in {args.perf_log}")

    # Choose max useful message case as default headline: enc ad32/msg32.
    headline = None
    for r in perf_rows:
        if r["decrypt"] == 0 and r["ad"] == 32 and r["msg"] == 32:
            headline = r
            break
    if headline is None:
        headline = max(perf_rows, key=lambda r: (r["msg"], r["ad"]))

    freqs = [float(x) for x in args.freqs.split(",") if x.strip()]
    tile_names = [x.strip() for x in args.tiles.split(",") if x.strip()]
    base_cost_extra = (0.0 if args.no_devkit else args.devkit_eur) + args.shipping_eur

    points = []
    csv_rows = []
    for tile in tile_names:
        ntiles = TILE_CHOICES[tile]
        cost = ntiles * args.tile_price_eur + base_cost_extra
        for mhz in freqs:
            hz = mhz * 1e6
            cycles = headline["cycles"]
            latency_s = cycles / hz
            ops_s = hz / cycles
            payload_mbps = (headline["msg"] * 8 * ops_s) / 1e6
            p = {
                "tiles": tile,
                "tile_count": ntiles,
                "freq_mhz": mhz,
                "cost_eur": cost,
                "cycles": cycles,
                "latency_us": latency_s * 1e6,
                "ops_per_s": ops_s,
                "throughput_mbps": payload_mbps,
            }
            points.append(p)
            csv_rows.append(p)

    csv_path = out_dir / "perf_cost_table.csv"
    with csv_path.open("w", newline="") as fh:
        fieldnames = ["tiles", "tile_count", "freq_mhz", "cost_eur", "cycles", "latency_us", "ops_per_s", "throughput_mbps"]
        writer = csv.DictWriter(fh, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(csv_rows)

    svg_path = out_dir / "cost_throughput.svg"
    svg_plot(points, svg_path)

    md_path = out_dir / "perf_cost_report.md"
    with md_path.open("w") as fh:
        fh.write("# TT-16 performance/cost model\n\n")
        fh.write("## Measured core cycles\n\n")
        fh.write("| decrypt | AD bytes | message bytes | cycles |\n")
        fh.write("|---:|---:|---:|---:|\n")
        for r in perf_rows:
            fh.write(f"| {r['decrypt']} | {r['ad']} | {r['msg']} | {r['cycles']} |\n")
        fh.write("\n")
        fh.write("## Headline case\n\n")
        fh.write(f"Using decrypt={headline['decrypt']}, AD={headline['ad']} B, message={headline['msg']} B, cycles={headline['cycles']}.\n\n")
        fh.write("## Cost/performance table\n\n")
        fh.write("| tiles | tile count | freq MHz | cost € | latency µs | ops/s | payload Mbit/s |\n")
        fh.write("|---|---:|---:|---:|---:|---:|---:|\n")
        for p in points:
            fh.write(f"| {p['tiles']} | {p['tile_count']} | {p['freq_mhz']:.0f} | {p['cost_eur']:.0f} | {p['latency_us']:.2f} | {p['ops_per_s']:.0f} | {p['throughput_mbps']:.3f} |\n")
        fh.write("\n")
        fh.write(f"CSV: `{csv_path}`\n\n")
        fh.write(f"SVG plot: `{svg_path}`\n")

    print(md_path)
    print(csv_path)
    print(svg_path)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
