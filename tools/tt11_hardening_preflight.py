#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

failures: list[str] = []
warnings: list[str] = []

def ok(msg: str) -> None:
    print(f"[OK]   {msg}")

def warn(msg: str) -> None:
    warnings.append(msg)
    print(f"[WARN] {msg}")

def fail(msg: str) -> None:
    failures.append(msg)
    print(f"[FAIL] {msg}")

def run(cmd: list[str]) -> tuple[int, str]:
    try:
        out = subprocess.check_output(cmd, text=True, stderr=subprocess.STDOUT)
        return 0, out.strip()
    except subprocess.CalledProcessError as e:
        return e.returncode, e.output.strip()
    except Exception as e:
        return 127, str(e)

def git(args: list[str]) -> str | None:
    code, out = run(["git", *args])
    return out if code == 0 else None

def read(path: str | Path) -> str:
    return Path(path).read_text(errors="replace")

print(f"[INFO] repo: {Path('.').resolve()}")

# Basic repo state.
head = git(["rev-parse", "--short", "HEAD"])
branch = git(["branch", "--show-current"])
if head:
    print(f"[INFO] git: {branch or '?'} {head}")
else:
    warn("not a Git repo or git unavailable")

status = git(["status", "--short"])
if status:
    warn("working tree has local changes; commit before hardening if this is intentional:\n       " + "\n       ".join(status.splitlines()))
else:
    ok("working tree clean")

# Required project files.
for f in ["info.yaml", "src/project.v", "docs/info.md", "docs/protocol.md", "docs/area_summary.md"]:
    if Path(f).exists():
        ok(f"has {f}")
    else:
        fail(f"missing {f}")

# TT top module and port shape.
project = read("src/project.v")
if re.search(r"\bmodule\s+tt_um_ascon_aead\b", project):
    ok("top module tt_um_ascon_aead present")
else:
    fail("top module tt_um_ascon_aead missing")

for port in ["ui_in", "uo_out", "uio_in", "uio_out", "uio_oe", "ena", "clk", "rst_n"]:
    if re.search(rf"\b{port}\b", project):
        ok(f"TT port present: {port}")
    else:
        fail(f"TT port missing: {port}")

# Check production defaults are the compile-time default when TT_DEBUG_DEFAULTS is not set.
for macro in [
    "TT_ASCON_DEF_ENABLE_PERM_DEBUG 0",
    "TT_ASCON_DEF_ENABLE_DIAGNOSTICS 0",
    "TT_ASCON_DEF_ENABLE_OUT_BUFFER 0",
]:
    if macro in project:
        ok(f"production macro default found: {macro}")
    else:
        fail(f"production macro default not found: {macro}")

# Check info.yaml source_files are local and exist.
info = read("info.yaml")
source_files = []
in_block = False
for line in info.splitlines():
    if re.match(r"^\s*source_files\s*:\s*$", line):
        in_block = True
        continue
    if in_block:
        if not line.strip():
            continue
        if re.match(r"^\S", line):
            break
        m = re.match(r"^\s*-\s*(.+?)\s*$", line)
        if m:
            source_files.append(m.group(1).strip().strip("'\""))

if not source_files:
    fail("info.yaml source_files is empty or missing")
else:
    ok(f"info.yaml has {len(source_files)} source_files entries")

external = [f for f in source_files if f.startswith("../") or f.startswith("/")]
if external:
    fail("source_files contains external paths:\n       " + "\n       ".join(external))
else:
    ok("source_files contains no external paths")

missing = [f for f in source_files if not Path(f).is_file()]
if missing:
    fail("source_files missing on disk:\n       " + "\n       ".join(missing))
else:
    ok("all source_files exist on disk")

# Check hardening tool prerequisites without requiring them to be installed yet.
py = shutil.which("python3")
if py:
    code, out = run([py, "--version"])
    ok(f"python3 available: {out}")
else:
    fail("python3 not found")

docker = shutil.which("docker") or shutil.which("podman")
if docker:
    code, out = run([docker, "--version"])
    if code == 0:
        ok(f"container engine available: {out}")
    else:
        warn(f"container engine command failed: {out}")
else:
    warn("docker/podman not found; local hardening will need a container engine")

tt_tool = Path("tt/tt_tool.py")
if tt_tool.exists():
    ok("tt/tt_tool.py exists")
else:
    warn("tt/tt_tool.py not found; clone tt-support-tools into ./tt before local hardening")

for env in ["PDK_ROOT", "PDK", "LIBRELANE_TAG"]:
    val = os.environ.get(env)
    if val:
        ok(f"{env}={val}")
    else:
        warn(f"{env} not set")

# Existing hardening outputs, if any.
if Path("runs").exists():
    warn("runs/ exists; review whether it is stale before trusting hardening reports")
else:
    ok("no existing runs/ directory")

if Path("src/user_config.json").exists():
    ok("src/user_config.json exists")
else:
    warn("src/user_config.json not found yet; generate it with ./tt/tt_tool.py --create-user-config")

print()
if failures:
    print(f"[FAIL] TT-11 hardening preflight failed with {len(failures)} failure(s), {len(warnings)} warning(s).")
    sys.exit(1)

print(f"[OK]   TT-11 hardening preflight passed with {len(warnings)} warning(s).")
print()
print("Next hardening commands, once tt-support-tools/env are installed:")
print("  ./tt/tt_tool.py --create-user-config")
print("  ./tt/tt_tool.py --harden")
print("  ./tt/tt_tool.py --print-warnings")
