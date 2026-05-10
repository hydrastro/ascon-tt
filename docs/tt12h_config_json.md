# TT-12H — Add `src/config.json`

`tt-support-tools` calls `read_config("src/config")` while creating the merged
LibreLane configuration. Therefore the project must contain `src/config.json`.

The file is intentionally close to the Tiny Tapeout Verilog template default,
with a conservative 25 MHz clock target:

```json
"CLOCK_PERIOD": 40,
"CLOCK_PORT": "clk",
"PL_TARGET_DENSITY_PCT": 60
```

The next hardening run may still fail later in placement/routing/timing. That is
a real physical-flow result. The missing-config failure was only a metadata/
configuration setup blocker.

If `tt12b-after-harden` is run before a completed hardening run exists, report
printing is skipped to avoid misleading `IndexError` tracebacks from missing
report files.
