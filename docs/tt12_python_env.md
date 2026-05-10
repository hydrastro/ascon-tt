# TT-12 Python environment for Tiny Tapeout tools

`tt/tt_tool.py` imports Python packages from `tt/requirements.txt`. Do not chase
these one by one in `flake.nix`; use Nix for system tools and a repo-local venv
for the Python dependency set pinned by `tt-support-tools`.

Inside `nix develop`:

```sh
make tt12-python-venv
source .venv/bin/activate
make tt12-python-check
```

Then run:

```sh
./tt/tt_tool.py --create-user-config
./tt/tt_tool.py --harden
./tt/tt_tool.py --print-warnings
```

If `ModuleNotFoundError: No module named 'chevron'` appears, the command is not
using `.venv/bin/python`. Check:

```sh
which python3
python3 -c "import sys; print(sys.executable)"
python3 -c "import chevron; print(chevron.__file__)"
```
