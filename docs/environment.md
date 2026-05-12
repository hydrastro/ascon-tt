# Development and hardening environment

This repository uses a two-layer environment:

1. **Nix shell** provides native executables and native shared libraries:
   Yosys, Icarus, Verilator, OpenROAD, KLayout, Docker client, DVC, Cairo/X11
   runtime libraries, etc.
2. **`.venv`** provides Tiny Tapeout Python dependencies from
   `tt/requirements.txt`, plus the selected `librelane==$LIBRELANE_TAG`.

Do not add TT Python packages one by one to `flake.nix`. The support-tools
requirements are the source of truth.

## First setup

```sh
git submodule update --init --recursive
nix develop
make tt-env-bootstrap
make tt-env-check
```

## Running Tiny Tapeout tools

Always run `tt_tool.py` through the environment wrapper so `.venv/bin` is first
in `PATH`. This is required because `tt_tool.py --create-user-config` calls the
`yowasp-yosys` executable from the Python package.

```sh
make tt-create-user-config
make tt-harden
make tt-print-warnings
```

Equivalent direct form:

```sh
tools/tt_env_run.sh .venv/bin/python ./tt/tt_tool.py --create-user-config
tools/tt_env_run.sh .venv/bin/python ./tt/tt_tool.py --harden
```

## Why `yowasp-yosys` was missing

`yowasp-yosys` is installed by `pip install -r tt/requirements.txt` into
`.venv/bin`. If `.venv/bin` is not on `PATH`, `tt_tool.py` will fail while
trying to probe the design ports.
