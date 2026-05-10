#!/usr/bin/env python3
from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(".").resolve()

def sh(cmd: list[str], cwd: Path | None = None) -> str:
    try:
        return subprocess.check_output(cmd, cwd=cwd, text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return "unknown"

def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()

def file_record(path: Path, base: Path) -> dict[str, object]:
    st = path.stat()
    return {
        "path": str(path.relative_to(base)),
        "bytes": st.st_size,
        "sha256": sha256(path),
    }

def collect_files(base: Path) -> list[dict[str, object]]:
    records: list[dict[str, object]] = []
    if not base.exists():
        return records
    for p in sorted(base.rglob("*")):
        if p.is_file():
            records.append(file_record(p, base))
    return records

def main() -> int:
    if len(sys.argv) < 2:
        print("usage: tt12a_make_manifest.py <artifact-dir> [output.json]", file=sys.stderr)
        return 2

    artifact_dir = Path(sys.argv[1]).resolve()
    out = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else artifact_dir / "manifest.json"

    if not artifact_dir.exists():
        print(f"ERROR: artifact dir does not exist: {artifact_dir}", file=sys.stderr)
        return 1

    submodule_status = sh(["git", "submodule", "status", "--recursive"])
    git_head = sh(["git", "rev-parse", "HEAD"])
    git_short = sh(["git", "rev-parse", "--short", "HEAD"])
    git_branch = sh(["git", "branch", "--show-current"])
    dirty = sh(["git", "status", "--short"])

    tt_head = "unknown"
    tt_path = ROOT / "tt"
    if tt_path.exists():
        tt_head = sh(["git", "rev-parse", "HEAD"], cwd=tt_path)

    data = {
        "created_utc": datetime.now(timezone.utc).isoformat(),
        "repo": str(ROOT),
        "artifact_dir": str(artifact_dir),
        "git": {
            "branch": git_branch,
            "head": git_head,
            "short": git_short,
            "dirty": dirty,
            "submodules": submodule_status,
            "tt_support_tools_head": tt_head,
        },
        "environment": {
            "PDK_ROOT": os.environ.get("PDK_ROOT", ""),
            "PDK": os.environ.get("PDK", ""),
            "LIBRELANE_TAG": os.environ.get("LIBRELANE_TAG", ""),
        },
        "files": collect_files(artifact_dir),
    }

    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(data, indent=2, sort_keys=True) + "\n")
    print(out)
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
