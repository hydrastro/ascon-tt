#!/usr/bin/env python3
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

try:
    import yaml
except Exception as e:
    print(f"[FAIL] cannot import yaml: {e}")
    sys.exit(1)

failures: list[str] = []
warnings: list[str] = []

def ok(msg: str) -> None:
    print(f"[OK]   {msg}")

def fail(msg: str) -> None:
    failures.append(msg)
    print(f"[FAIL] {msg}")

def warn(msg: str) -> None:
    warnings.append(msg)
    print(f"[WARN] {msg}")

def sh(cmd: list[str]) -> str:
    try:
        return subprocess.check_output(cmd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unknown"

def sf_path(entry: str) -> Path:
    p = Path(entry)
    if p.parts and p.parts[0] == "src":
        return p
    return Path("src") / p

root = Path(".").resolve()
print(f"[INFO] repo: {root}")
print(f"[INFO] git: {sh(['git','branch','--show-current'])} {sh(['git','rev-parse','--short','HEAD'])}")

info_path = Path("info.yaml")
if not info_path.exists():
    fail("missing info.yaml")
    info = {}
else:
    info = yaml.safe_load(info_path.read_text()) or {}

project = info.get("project") or {}
source_files = project.get("source_files") or info.get("source_files") or []

if info.get("yaml_version") == 6:
    ok("info.yaml yaml_version is 6")
else:
    fail("info.yaml yaml_version must be 6")

valid_tiles = {"1x1","1x2","2x2","3x2","4x2","6x2","8x2"}
if project.get("tiles") in valid_tiles:
    ok(f"info.yaml project.tiles is valid: {project.get('tiles')}")
else:
    fail(f"info.yaml project.tiles is invalid: {project.get('tiles')!r}")

if project.get("top_module") == "tt_um_ascon_aead":
    ok("info.yaml project.top_module is tt_um_ascon_aead")
else:
    fail("info.yaml project.top_module is not tt_um_ascon_aead")

if source_files:
    ok(f"info.yaml project.source_files has {len(source_files)} entries")
else:
    fail("info.yaml project.source_files is missing/empty")

for s in source_files:
    s = str(s)
    if s.startswith("../") or s.startswith("/"):
        fail(f"source file uses external path: {s}")
    elif sf_path(s).is_file():
        ok(f"source file exists: {sf_path(s)}")
    else:
        fail(f"source file missing: {sf_path(s)}")

pinout = info.get("pinout") or {}
required_pins = [f"ui[{i}]" for i in range(8)] + [f"uo[{i}]" for i in range(8)] + [f"uio[{i}]" for i in range(8)]
missing_pins = [p for p in required_pins if p not in pinout]
if missing_pins:
    fail("pinout is missing pins: " + ", ".join(missing_pins))
else:
    ok("pinout has all ui/uo/uio pins")

project_v = Path("src/project.v")
if project_v.exists() and re.search(r"\bmodule\s+tt_um_ascon_aead\b", project_v.read_text(errors="replace")):
    ok("top module tt_um_ascon_aead exists in src/project.v")
else:
    fail("top module tt_um_ascon_aead missing in src/project.v")

for f in [
    "src/ascon_core/ascon_round_comb.v",
    "src/ascon_core/ascon_perm_unrolled.v",
    "src/ascon_core/ascon_aead128_enc_ad.v",
    "src/ascon_core/ascon_aead128_dec_ad.v",
]:
    if Path(f).exists():
        ok(f"core RTL packaged in repo: {f}")
    else:
        fail(f"missing packaged core RTL: {f}")

bad: list[str] = []
for p in Path(".").rglob("*"):
    parts = set(p.parts)
    if not p.is_file():
        continue
    if ".git" in parts or "build" in parts or ".venv" in parts or "tt" in parts:
        continue
    if p.parts[:2] == ("artifacts", "runs") or p.parts[:2] == ("sim", "generated"):
        continue
    if p.suffix in {".rej", ".orig", ".patch", ".zip"} or p.name.endswith(".tar.gz"):
        bad.append(str(p))
if bad:
    fail("stale/archive artifacts outside ignored dirs:\n       " + "\n       ".join(bad[:80]))
else:
    ok("no stale/archive artifacts outside ignored dirs")

status = sh(["git", "status", "--short"])
if status != "unknown" and status:
    warn("working tree has local changes:\n       " + "\n       ".join(status.splitlines()))
else:
    ok("working tree clean")

if failures:
    print(f"\n[FAIL] TT-10 flow preflight failed with {len(failures)} failure(s), {len(warnings)} warning(s).")
    sys.exit(1)
print(f"\n[OK]   TT-10 flow preflight passed with {len(warnings)} warning(s).")
