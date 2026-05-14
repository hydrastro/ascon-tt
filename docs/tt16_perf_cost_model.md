# TT-16 — Performance and cost model

This checkpoint answers four questions:

1. How many cycles does one full AEAD operation take?
2. What latency/throughput do we get at 5, 10, 25, and 50 MHz?
3. How does tile count map to cost?
4. Which tile/frequency points are worth hardening?

## Important distinction

Cost depends on tile count, not frequency. Frequency affects performance and
timing closure risk.

## Run

```sh
make sim-perf-cycles
make tt16-perf-cost
cat build/tt16/perf_cost_report.md
```

This measures the shared core directly. It does not include external serial I/O
loading time. For software-visible time over the Tiny Tapeout byte protocol, add
the command/input/output byte transfer time on top.

## Budget reality

At 70 EUR/tile:

| tile setting | tiles | tile-only EUR |
|---|---:|---:|
| 2x2 | 4 | 280 |
| 3x2 | 6 | 420 |
| 4x2 | 8 | 560 |
| 6x2 | 12 | 840 |
| 8x2 | 16 | 1120 |

If a devkit/PCB is required, add that separately.
