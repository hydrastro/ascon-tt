#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(".").resolve()
failures: list[str] = []
warnings: list[str] = []

REQUIRED_TOP = "tt_um_ascon_aead"
REQUIRED_PORTS = [
    "ui_in",
    "uo_out",
    "uio_in",
    "uio_out",
    "uio_oe",
    "ena",
    "clk",
    "rst_n",
]
REQUIRED_LOCAL_RTL = [
    "src/project.v",
    "src/ascon_tt_serial_frontend.v",
    "src/ascon_tt_aead_bridge.v",
    "src/ascon_tt_perm_core.v",
    "src/ascon_tt_aead_core_stub.v",
]
REQUIRED_CORE_RTL_NAMES = [
    "ascon_round_comb.v",
    "ascon_perm_unrolled.v",
    "ascon_aead128_enc_ad.v",
    "ascon_aead128_dec_ad.v",
]

def ok(msg: str) -> None:
    print(f"[OK]   {msg}")

def warn(msg: str) -> None:
    warnings.append(msg)
    print(f"[WARN] {msg}")

def fail(msg: str) -> None:
    failures.append(msg)
    print(f"[FAIL] {msg}")

def read(path: str | Path) -> str:
    return Path(path).read_text(errors="replace")

def git(args: list[str]) -> str | None:
    try:
        return subprocess.check_output(["git", *args], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return None

def source_files_from_info(info: str) -> list[str]:
    # Minimal YAML-ish parser for common TT info.yaml style:
    # source_files:
    #   - src/foo.v
    files: list[str] = []
    in_block = False
    indent = None
    for line in info.splitlines():
        raw = line.rstrip()
        if re.match(r"^\s*source_files\s*:\s*$", raw):
            in_block = True
            indent = None
            continue
        if in_block:
            if not raw.strip():
                continue
            if re.match(r"^\S", raw):
                break
            m = re.match(r"^(\s*)-\s*(.+?)\s*$", raw)
            if m:
                indent = len(m.group(1)) if indent is None else indent
                item = m.group(2).strip().strip("'\"")
                files.append(item)
    return files

print(f"[INFO] repo: {ROOT}")
head = git(["rev-parse", "--short", "HEAD"])
branch = git(["branch", "--show-current"])
if head:
    print(f"[INFO] git: {branch or '?'} {head}")
else:
    warn("git metadata unavailable")

# Project top inspection.
project_path = Path("src/project.v")
if not project_path.exists():
    fail("missing src/project.v")
else:
    project = read(project_path)
    if re.search(rf"\bmodule\s+{re.escape(REQUIRED_TOP)}\b", project):
        ok(f"top module {REQUIRED_TOP} exists in src/project.v")
    else:
        fail(f"top module {REQUIRED_TOP} not found in src/project.v")

    for port in REQUIRED_PORTS:
        if re.search(rf"\b{re.escape(port)}\b", project):
            ok(f"top references TT port {port}")
        else:
            fail(f"top missing TT port {port}")

    for name, value in [
        ("ENABLE_PERM_DEBUG", "0"),
        ("ENABLE_DIAGNOSTICS", "0"),
        ("ENABLE_OUT_BUFFER", "0"),
        ("MAX_AD_BYTES", "32"),
        ("MAX_DATA_BYTES", "32"),
    ]:
        if re.search(rf"\bparameter\s+integer\s+{re.escape(name)}\s*=\s*(?:`TT_ASCON_DEF_[A-Z_]+|{value})\b", project):
            ok(f"top parameter {name} has production-compatible default")
        else:
            fail(f"top parameter {name} is not production-compatible")

# info.yaml inspection.
info_path = Path("info.yaml")
if not info_path.exists():
    fail("missing info.yaml")
    info = ""
else:
    info = read(info_path)
    if re.search(rf"^\s*top_module\s*:\s*['\"]?{re.escape(REQUIRED_TOP)}['\"]?\s*$", info, flags=re.M):
        ok(f"info.yaml top_module is {REQUIRED_TOP}")
    else:
        fail(f"info.yaml top_module is not {REQUIRED_TOP}")

    source_files = source_files_from_info(info)
    if source_files:
        ok(f"info.yaml has {len(source_files)} source_files entries")
    else:
        fail("info.yaml source_files missing or empty")

    for f in REQUIRED_LOCAL_RTL:
        if f in source_files:
            ok(f"info.yaml source_files includes {f}")
        else:
            fail(f"info.yaml source_files missing {f}")

    missing_on_disk = [f for f in source_files if not Path(f).exists()]
    if missing_on_disk:
        fail("info.yaml source_files entries missing on disk:\n       " + "\n       ".join(missing_on_disk))
    else:
        ok("all info.yaml source_files entries exist on disk")

    external_source_files = [f for f in source_files if f.startswith("../") or f.startswith("/")]
    if external_source_files:
        fail("info.yaml source_files contains external paths, unsafe for TT submission:\n       " + "\n       ".join(external_source_files))
    else:
        ok("info.yaml source_files has no external paths")

# Core RTL packaging. This catches the ../ascon-rtl problem early.
repo_files = {p.name: str(p) for p in Path(".").rglob("*.v") if ".git" not in p.parts and "build" not in p.parts}
for name in REQUIRED_CORE_RTL_NAMES:
    if name in repo_files:
        ok(f"core RTL packaged in repo: {repo_files[name]}")
    else:
        fail(f"core RTL not packaged in repo: {name}")

# Makefile and docs targets.
makefile = read("Makefile") if Path("Makefile").exists() else ""
for target in ["tt9-release-check", "tt10-flow-preflight", "tt10-release-check"]:
    if re.search(rf"(^|\n){re.escape(target)}\s*:", makefile):
        ok(f"Makefile has target {target}")
    else:
        fail(f"Makefile missing target {target}")

# Artifact hygiene.
stale = []
for p in ROOT.rglob("*"):
    rel = p.relative_to(ROOT)
    if ".git" in rel.parts or "build" in rel.parts:
        continue
    if p.is_file() and (p.suffix in {".rej", ".orig", ".patch", ".zip"} or p.name.endswith(".tar.gz")):
        stale.append(str(rel))
if stale:
    fail("stale/archive artifacts outside build/.git:\n       " + "\n       ".join(stale[:40]))
else:
    ok("no stale/archive artifacts outside build/.git")

status = git(["status", "--short"])
if status:
    warn("working tree has local changes:\n       " + "\n       ".join(status.splitlines()))
else:
    ok("working tree clean")

print()
if failures:
    print(f"[FAIL] TT-10 flow preflight failed with {len(failures)} failure(s), {len(warnings)} warning(s).")
    sys.exit(1)
print(f"[OK]   TT-10 flow preflight passed with {len(warnings)} warning(s).")
