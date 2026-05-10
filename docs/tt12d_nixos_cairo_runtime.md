# TT-12D — NixOS Cairo runtime for Tiny Tapeout tools

After fixing `libstdc++.so.6` for the Python `klayout` wheel, the next native
runtime failure was:

```text
OSError: no library called "cairo-2" was found
cannot load library 'libcairo.so.2'
```

This comes from `cairosvg -> cairocffi`, which is imported by
`tt/render_utils.py`.

The fix is to expose Cairo and its runtime dependencies through the Nix dev
shell `LD_LIBRARY_PATH`.

The shell also uses renamed top-level Nix package attributes like `libx11`,
`libxext`, and `libxcb` instead of deprecated `xorg.libX11`-style names.

Recommended sequence:

```sh
exit
nix develop
make tt12-python-reset
make tt12-python-venv
make tt12-python-check
```

Expected check output:

```text
tt python deps + klayout + cairosvg OK
```
