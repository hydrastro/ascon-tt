#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
if [ ! -x .venv/bin/python ]; then
  echo "ERROR: .venv is missing. Run: make tt-env-bootstrap" >&2
  exit 1
fi
export PATH="$ROOT/.venv/bin:$PATH"
export PDK_ROOT="${PDK_ROOT:-$ROOT/.ttsetup/pdk}"
export PDK="${PDK:-sky130A}"
export LIBRELANE_TAG="${LIBRELANE_TAG:-3.0.0rc1}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"
exec "$@"
