#!/usr/bin/env python3
"""
Patch librelane/common/tcl.py to use tclsh subprocess instead of tkinter.

Run once after make tt12-python-venv (while inside nix develop):
  python3 tools/patch_librelane_tcl.py
"""
import sys, re
from pathlib import Path


def find_tcl_py():
    venv = Path(".venv")
    for p in venv.rglob("librelane/common/tcl.py"):
        return p
    return None


def patch():
    tcl_py = find_tcl_py()
    if tcl_py is None:
        print("ERROR: .venv/*/librelane/common/tcl.py not found.")
        print("Run: make tt12-python-venv first.")
        sys.exit(1)

    text = tcl_py.read_text()

    if "# PATCHED_TCLSH" in text:
        print(f"Already patched: {tcl_py}")
        return

    # The function we need to patch is TclUtils._eval_env.
    # It uses tkinter to evaluate a TCL script.
    # We replace it with a tclsh subprocess call.
    # 
    # The replacement is safe because _eval_env is only used to read
    # PDK config.tcl files, and tclsh evaluates the same TCL.

    old_pattern = "        import tkinter"
    if old_pattern not in text:
        print(f"Pattern not found in {tcl_py}")
        print("Showing lines 55-75:")
        for i, l in enumerate(text.split("\n")[54:75], 55):
            print(f"  {i}: {l}")
        print()
        print("Trying alternative patch: replacing entire _eval_env body...")
        # Alternative: find and replace the entire _eval_env function
        alt_old = re.search(
            r"    @staticmethod\n    def _eval_env.*?(?=\n    @|\nclass |\Z)",
            text, re.DOTALL
        )
        if not alt_old:
            print("Cannot locate _eval_env — manual patch required.")
            sys.exit(1)
        
        new_func = (
            "    @staticmethod\n"
            "    def _eval_env(env, script):  # PATCHED_TCLSH\n"
            "        import subprocess, shutil, os\n"
            "        tclsh = shutil.which(\"tclsh\")\n"
            "        if tclsh is None:\n"
            "            raise RuntimeError(\"tclsh not found in PATH. "
                        "Add tcl to your nix shell or install tkinter.\")\n"
            "        proc = subprocess.run(\n"
            "            [tclsh],\n"
            "            input=script,\n"
            "            capture_output=True,\n"
            "            text=True,\n"
            "            env={**os.environ, **env},\n"
            "        )\n"
            "        return proc.stdout\n"
        )
        text = text[:alt_old.start()] + new_func + text[alt_old.end():]
        tcl_py.write_text(text)
        print(f"Patched (alt method): {tcl_py}")
        return

    # Standard patch: replace tkinter import + usage with tclsh subprocess
    # Find the full block starting at "import tkinter"
    lines = text.split("\n")
    patch_start = None
    patch_end   = None
    for i, l in enumerate(lines):
        if l.strip() == "import tkinter":
            patch_start = i
        if patch_start is not None and i > patch_start:
            # The block ends when indentation returns to method level
            # or we hit the return statement
            if l.strip().startswith("return ") and "    " in l:
                patch_end = i
                break

    if patch_start is None or patch_end is None:
        print(f"Could not find patch boundaries. Lines 55-75:")
        for i, l in enumerate(lines[54:75], 55):
            print(f"  {i}: {l}")
        sys.exit(1)

    print(f"Patching lines {patch_start+1}-{patch_end+1}")
    indent = "        "  # 8 spaces (method body indentation)
    replacement = [
        f"{indent}# PATCHED_TCLSH: replaced tkinter with subprocess tclsh",
        f"{indent}import subprocess, shutil, os as _os",
        f"{indent}_tclsh = shutil.which(\"tclsh\")",
        f"{indent}if _tclsh is None:",
        f"{indent}    raise RuntimeError(\"tclsh not found. Add tcl to flake.nix packages.\")",
        f"{indent}_proc = subprocess.run(",
        f"{indent}    [_tclsh],",
        f"{indent}    input=script,",
        f"{indent}    capture_output=True,",
        f"{indent}    text=True,",
        f"{indent}    env={{**_os.environ, **env}},",
        f"{indent})",
        f"{indent}return _proc.stdout",
    ]
    lines = lines[:patch_start] + replacement + lines[patch_end+1:]
    tcl_py.write_text("\n".join(lines))
    print(f"Patched: {tcl_py}")
    print("Test with: python3 -c \"from librelane.common.tcl import TclUtils; print('OK')\"")


if __name__ == "__main__":
    patch()
