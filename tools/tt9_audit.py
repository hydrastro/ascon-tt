#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(".").resolve()
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

def read(path: str) -> str:
    return Path(path).read_text(errors="replace")

def require_file(path: str) -> None:
    ok(f"has {path}") if Path(path).is_file() else fail(f"missing {path}")

def git(args: list[str]) -> str | None:
    try:
        return subprocess.check_output(["git", *args], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return None

print(f"[INFO] repo: {ROOT}")
branch = git(["branch", "--show-current"])
head = git(["rev-parse", "--short", "HEAD"])
if branch and head:
    print(f"[INFO] git: {branch} {head}")
else:
    warn("git metadata unavailable")

for path in [
    ".gitignore", "Makefile", "info.yaml",
    "src/project.v", "src/ascon_tt_serial_frontend.v",
    "src/ascon_tt_aead_bridge.v", "src/ascon_tt_perm_core.v",
    "docs/info.md", "docs/architecture.md", "tools/report_tt5_profiles.py",
]:
    require_file(path)

stale = []
for p in ROOT.rglob("*"):
    rel = p.relative_to(ROOT)
    parts = rel.parts
    if ".git" in parts or "build" in parts:
        continue
    if p.is_file() and (
        p.suffix in {".rej", ".orig", ".patch", ".zip"}
        or p.name.endswith(".tar.gz")
        or p.suffix in {".vvp", ".vcd", ".fst"}
    ):
        stale.append(str(rel))

if stale:
    fail("stale/archive/simulator artifacts outside build/.git:\n       " + "\n       ".join(stale[:40]))
else:
    ok("no stale/archive/simulator artifacts outside build/.git")

tracked = git(["ls-files"]) or ""
bad_tracked = []
for line in tracked.splitlines():
    if line.startswith("build/") or line.endswith((".vvp", ".vcd", ".fst", ".rej", ".orig", ".zip", ".tar.gz")):
        bad_tracked.append(line)
if bad_tracked:
    fail("tracked generated/stale artifacts:\n       " + "\n       ".join(sorted(set(bad_tracked))))
else:
    ok("no tracked build/stale artifacts")

project = read("src/project.v")
frontend = read("src/ascon_tt_serial_frontend.v")
makefile = read("Makefile")

def expect_param(text: str, module: str, name: str, value: str) -> None:
    m = re.search(rf"\bmodule\s+{re.escape(module)}\b.*?;", text, flags=re.S)
    if not m:
        fail(f"cannot find module header {module}")
        return
    header = m.group(0)
    if re.search(rf"\bparameter\s+integer\s+{re.escape(name)}\s*=\s*{re.escape(value)}\b", header):
        ok(f"{module}.{name} default is {value}")
    else:
        fail(f"{module}.{name} default is not {value}")

for name, value in [
    ("ENABLE_PERM_DEBUG", "0"),
    ("ENABLE_DIAGNOSTICS", "0"),
    ("ENABLE_OUT_BUFFER", "0"),
    ("MAX_AD_BYTES", "32"),
    ("MAX_DATA_BYTES", "32"),
]:
    expect_param(project, "tt_um_ascon_aead", name, value)

for name, value in [
    ("ENABLE_PERM_DEBUG", "1"),
    ("ENABLE_DIAGNOSTICS", "1"),
    ("ENABLE_OUT_BUFFER", "1"),
    ("MAX_AD_BYTES", "32"),
    ("MAX_DATA_BYTES", "32"),
]:
    expect_param(frontend, "ascon_tt_serial_frontend", name, value)

inst = re.search(r"ascon_tt_serial_frontend\s*#\s*\((.*?)\)\s*u_frontend", project, flags=re.S)
if not inst:
    fail("u_frontend is not explicitly parameterized")
else:
    body = inst.group(1)
    for name in ["ENABLE_PERM_DEBUG", "ENABLE_DIAGNOSTICS", "ENABLE_OUT_BUFFER", "MAX_AD_BYTES", "MAX_DATA_BYTES"]:
        if re.search(rf"\.{name}\s*\(\s*{name}\s*\)", body):
            ok(f"u_frontend passes {name}")
        else:
            fail(f"u_frontend does not pass {name}")

for target in [
    "sanity", "debug-regression", "sim-aead-vectors-prod-directout",
    "lint", "synth", "prod-default-report",
    "tt7a5-directout-buffer-matrix", "tt9-audit", "tt9-release-check",
]:
    if re.search(rf"(^|\n){re.escape(target)}\s*:", makefile):
        ok(f"Makefile has target {target}")
    else:
        fail(f"Makefile missing target {target}")

gitignore = read(".gitignore") if Path(".gitignore").exists() else ""
for pattern in ["build", "*.vvp", "*.vcd", "*.fst", "*.rej", "*.orig", "*.zip"]:
    if pattern in gitignore:
        ok(f".gitignore covers {pattern}")
    else:
        warn(f".gitignore may not cover {pattern}")

status = git(["status", "--short"])
if status:
    warn("working tree has local changes:\n       " + "\n       ".join(status.splitlines()))
else:
    ok("working tree clean")

print()
if failures:
    print(f"[FAIL] TT-9 audit failed with {len(failures)} failure(s), {len(warnings)} warning(s).")
    sys.exit(1)
print(f"[OK]   TT-9 audit passed with {len(warnings)} warning(s).")
