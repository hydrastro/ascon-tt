# Area summary

Preferred Tiny Tapeout production default:

- `ENABLE_PERM_DEBUG=0`
- `ENABLE_DIAGNOSTICS=0`
- `ENABLE_OUT_BUFFER=0`
- `MAX_AD_BYTES=32`
- `MAX_DATA_BYTES=32`

Run:

```sh
make clean && make sanity
make synth
make prod-default-report
```

Expected current checkpoint:

| profile | cells | note |
|---|---:|---|
| production default / direct-output full AEAD | ~31.3k | full encrypt/decrypt, AD <= 32, data <= 32 |
| raw full AEAD bridge | ~27.1k | backend only, no TT byte frontend |
| debug full top | ~39k | permutation debug and diagnostics enabled |

Regenerate a markdown table from build logs:

```sh
python3 tools/tt9_area_summary.py build/yosys_tt_scaffold_stat.txt
```
