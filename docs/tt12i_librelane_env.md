# TT-12I — LibreLane install and PDK environment

`tt-support-tools` does not install LibreLane itself. Local hardening requires:

```sh
pip install librelane==$LIBRELANE_TAG
```

and these environment variables:

```sh
PDK_ROOT=<path-to-pdk-root>
PDK=<sky130A|gf180mcuD|ihp-sg13g2>
LIBRELANE_TAG=3.0.0rc1
```

The Makefile now defaults to:

```make
PDK_ROOT ?= $(CURDIR)/.ttsetup/pdk
PDK ?= sky130A
LIBRELANE_TAG ?= 3.0.0rc1
```

Override them when needed:

```sh
make tt12b-first-hardening-run PDK=gf180mcuD PDK_ROOT=/path/to/pdk LIBRELANE_TAG=3.0.0rc1
```

Recommended sequence:

```sh
make tt12-python-reset
make tt12-python-venv
make tt12-python-check
make tt12-env-check
make tt12-create-user-config
make tt12-harden
```
