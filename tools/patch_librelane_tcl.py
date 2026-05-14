#!/usr/bin/env python3
"""
Patch librelane/common/tcl.py to use tclsh subprocess instead of tkinter.
Safe to run multiple times (idempotent). Fixes the broken previous patch too.
"""
import sys, re
from pathlib import Path


def find_tcl_py():
    for p in Path(".venv").rglob("librelane/common/tcl.py"):
        return p
    return None


# The replacement _eval_env method — uses tclsh instead of tkinter
REPLACEMENT = (
    "    @staticmethod\n"
    "    def _eval_env(env, script):  # PATCHED_TCLSH\n"
    "        import subprocess, shutil, os as _os\n"
    "        _tclsh = shutil.which(\"tclsh\")\n"
    "        if _tclsh is None:\n"
    "            raise RuntimeError(\"tclsh not found. Add pkgs.tcl to flake.nix.\")\n"
    "        _proc = subprocess.run(\n"
    "            [_tclsh],\n"
    "            input=script,\n"
    "            capture_output=True,\n"
    "            text=True,\n"
    "            env={**_os.environ, **(env or {})},\n"
    "        )\n"
    "        return _proc.stdout\n"
)


def patch():
    tcl_py = find_tcl_py()
    if tcl_py is None:
        print("ERROR: .venv/*/librelane/common/tcl.py not found.")
        print("Run: make tt12-python-venv first.")
        sys.exit(1)

    text = tcl_py.read_text()

    # Remove any previous (possibly broken) patch
    if "# PATCHED_TCLSH" in text:
        print(f"Re-patching (removing previous patch): {tcl_py}")
        text = re.sub(
            r"    @staticmethod\n    def _eval_env\([^)]*\):  # PATCHED_TCLSH.*?"
            r"(?=\n    @staticmethod|\n    def (?!_eval_env)|\nclass |\Z)",
            "",
            text,
            flags=re.DOTALL,
        )

    # Find and replace the _eval_env method
    m = re.search(
        r"    @staticmethod\n    def _eval_env\(.*?"
        r"(?=\n    @staticmethod|\n    def (?!_eval_env)|\nclass |\Z)",
        text,
        re.DOTALL,
    )
    if not m:
        print(f"ERROR: _eval_env not found in {tcl_py}")
        print("Lines containing 'eval_env':")
        for i, l in enumerate(text.splitlines(), 1):
            if "eval_env" in l:
                print(f"  {i}: {l}")
        sys.exit(1)

    text = text[:m.start()] + REPLACEMENT + text[m.end():]
    tcl_py.write_text(text)
    print(f"Patched: {tcl_py}")

    # Verify
    result = __import__("subprocess").run(
        [sys.executable, "-c",
         "from librelane.common.tcl import TclUtils; print('TCL patch OK')"],
        capture_output=True, text=True,
    )
    msg = result.stdout.strip() or result.stderr.strip()
    print(msg if msg else "(no output from test)")


if __name__ == "__main__":
    patch()
