# TT-12A next commands

After TT-11B is committed and the hardening environment is available:

```sh
make tt12-first-hardening-run
```

After a run exists, capture it:

```sh
make tt12a-capture RUN_NAME=first_harden RUN_DIR=runs/wokwi
```

If the actual run directory is different, pass it explicitly:

```sh
make tt12a-capture RUN_NAME=first_harden RUN_DIR=<actual-run-dir>
```

Create a manifest for an already-captured artifact:

```sh
python3 tools/tt12a_make_manifest.py artifacts/runs/<run-dir>
```

Compare two captured runs:

```sh
python3 tools/tt12a_compare_manifests.py artifacts/manifests/old.json artifacts/manifests/new.json
```
