#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
if [ ! -f tt/requirements.txt ]; then
  echo "ERROR: tt/requirements.txt not found." >&2
  echo "Run: git submodule update --init --recursive" >&2
  exit 1
fi
PYTHON_BIN="${PYTHON_BIN:-python}"
LIBRELANE_TAG="${LIBRELANE_TAG:-3.0.0rc1}"
if [ ! -x .venv/bin/python ]; then
  echo "[tt-env] creating .venv with $PYTHON_BIN"
  "$PYTHON_BIN" -m venv .venv
fi
export PATH="$ROOT/.venv/bin:$PATH"
echo "[tt-env] upgrading packaging tools"
.venv/bin/python -m pip install --upgrade pip setuptools wheel
echo "[tt-env] installing Tiny Tapeout support-tool requirements"
.venv/bin/python -m pip install -r tt/requirements.txt
echo "[tt-env] installing LibreLane $LIBRELANE_TAG"
.venv/bin/python -m pip install "librelane==$LIBRELANE_TAG"
echo "[tt-env] done"
tools/tt_env_check.sh
