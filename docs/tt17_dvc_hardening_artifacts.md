# TT-17 — DVC hardening artifact capture

This flow captures physical-design outputs in a reproducible directory and
optionally stores them with DVC.

## One-command 4x2 capture

```sh
tools/tt17_capture_harden.sh \
  --tiles 4x2 \
  --clock-hz 10000000 \
  --store min-area \
  --name shared_4x2_10mhz \
  --branch min-area \
  --allow-dirty
```

## With DVC push

```sh
tools/tt17_capture_harden.sh \
  --tiles 4x2 \
  --clock-hz 10000000 \
  --store min-area \
  --name shared_4x2_10mhz \
  --dvc-remote myremote \
  --push
```

Artifact directory:

```text
artifacts/hardening/<store>/<name>/
```

Captured content:

- config before/used;
- git branch, commit, status, diff;
- hardening logs;
- GDS/DEF candidates if produced;
- optional KLayout screenshot;
- `manifest.md` with SHA-256 checksums;
- optional DVC `.dvc` metadata.

If hardening fails before GDS export, the artifact is still useful: logs,
configuration, and utilization failure data are captured.
