# Submission readiness checklist

Before using this repo with a Tiny Tapeout flow:

```sh
make clean && make sanity
make debug-regression
make sim-aead-vectors-prod-directout
make lint
make synth
make prod-default-report
make tt9-audit
```

Expected:

- debug regression passes;
- production AEAD vector test passes;
- Verilator lint passes;
- Yosys `check` reports 0 problems;
- default `make synth` is near 31.3k generic Yosys cells;
- no `.rej`, `.orig`, `.patch`, `.zip`, `.vvp`, `.vcd`, `.fst`, or `build/` products are tracked.

The top-level default must remain the production profile because external Tiny Tapeout flows usually synthesize default parameters unless explicitly configured otherwise.
