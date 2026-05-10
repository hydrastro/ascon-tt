# TT-12C — NixOS KLayout Python runtime fix

The failure:

```text
ImportError: libstdc++.so.6: cannot open shared object file: No such file or directory
```

comes from the Python `klayout` wheel inside `.venv`. The wheel is installed,
but on NixOS it cannot see the C++ runtime library unless the dev shell exposes
the relevant runtime libraries.

The fix is:

- use Nix for system/runtime libraries;
- use `.venv` for the Python package set from `tt/requirements.txt`;
- run `tt/tt_tool.py` explicitly through `.venv/bin/python`.

Recommended sequence:

```sh
nix develop
make tt12-python-reset
make tt12-python-venv
make tt12-python-check
```

The check intentionally imports:

```python
import klayout.db as pya
```

because that is the import that previously failed.

Do not commit `.venv`, `build/`, `runs/`, or generated layout artifacts.
