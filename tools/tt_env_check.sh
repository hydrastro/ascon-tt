#!/usr/bin/env bash
set -euo pipefail
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"
if [ ! -x .venv/bin/python ]; then
  echo "FAIL: .venv/bin/python missing. Run: make tt-env-bootstrap"
  exit 1
fi
export PATH="$ROOT/.venv/bin:$PATH"
export PDK_ROOT="${PDK_ROOT:-$ROOT/.ttsetup/pdk}"
export PDK="${PDK:-sky130A}"
export LIBRELANE_TAG="${LIBRELANE_TAG:-3.0.0rc1}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

echo "== Python =="
.venv/bin/python --version

echo
echo "== Required Python imports =="
.venv/bin/python - <<'PY'
mods = ["chevron", "yaml", "git", "requests", "mistune", "cairosvg", "klayout.db", "librelane"]
for m in mods:
    __import__(m)
print("imports OK")
PY

echo
echo "== Required executables =="
for exe in yowasp-yosys yosys iverilog verilator klayout openroad; do
  if command -v "$exe" >/dev/null 2>&1; then
    printf 'OK   %-16s %s\n' "$exe" "$(command -v "$exe")"
  else
    printf 'MISS %-16s\n' "$exe"
    exit 1
  fi
done
if command -v docker >/dev/null 2>&1; then
  printf 'OK   %-16s %s\n' docker "$(command -v docker)"
else
  echo "WARN docker not found; hardening needs host Docker or compatible container engine."
fi

echo
echo "== tt_tool import/help =="
tools/tt_env_run.sh .venv/bin/python ./tt/tt_tool.py --help >/dev/null
echo "tt_tool OK"

echo
echo "== env =="
echo "PDK_ROOT=$PDK_ROOT"
echo "PDK=$PDK"
echo "LIBRELANE_TAG=$LIBRELANE_TAG"
echo "PATH head=$(echo "$PATH" | tr ':' '\n' | head -3 | paste -sd ':' -)"
