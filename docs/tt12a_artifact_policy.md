# TT-12A — Layout artifact policy

This repo keeps source and metadata in Git. Generated layout/hardening artifacts
should not be committed directly to Git.

## What goes in Git

- RTL under `src/`
- tests and tools under `test/` and `tools/`
- `info.yaml`
- Makefile targets
- documentation
- small summary JSON/markdown files

## What goes in artifact storage / DVC

Generated hardening outputs, for example:

- GDS
- DEF
- LEF
- SPEF/SDF
- Magic/KLayout/DRC reports
- LVS/netgen reports
- OpenROAD/LibreLane/OpenLane logs
- timing reports
- run metrics

The helper scripts capture curated runs into:

```text
artifacts/runs/<timestamp>_<gitsha>_<pdk>_<name>/
artifacts/manifests/<timestamp>_<gitsha>_<pdk>_<name>.json
```

## DVC recommendation

DVC is optional but recommended once the first hardening run produces useful
artifacts.

Suggested flow after DVC is installed:

```sh
dvc init
dvc add artifacts/runs
git add .dvc .dvcignore artifacts/runs.dvc artifacts/manifests
git commit -m "Track hardening artifacts with DVC"
```

Then configure your storage backend. Examples:

```sh
dvc remote add -d localstore /path/to/ascon-tt-dvc-store
dvc push
```

or use an S3/NAS/SSH backend if desired.

## PDK portability

RTL and tests should stay as PDK-independent as possible. Generated GDS/layout
artifacts are PDK-specific by nature because layers, standard cells, timing
libraries, DRC rules, extraction, fill, and routing constraints come from the
selected PDK/toolchain.

Therefore each artifact manifest records:

- RTL Git commit
- submodule status
- `PDK`
- `PDK_ROOT`
- `LIBRELANE_TAG`
- file hashes

This is what makes two GDS/layout runs comparable.
