#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/tt12b
PY_TT="${PY_TT:-.venv/bin/python}"
export PATH="$(pwd)/.venv/bin:$PATH"
export PDK_ROOT="${PDK_ROOT:-$(pwd)/.ttsetup/pdk}"
export PDK="${PDK:-sky130A}"
export LIBRELANE_TAG="${LIBRELANE_TAG:-3.0.0rc1}"

RUN_DIR="${RUN_DIR:-}"
RUN_NAME="${RUN_NAME:-first_harden}"

echo "[INFO] Printing Tiny Tapeout warnings/stats if available..."
if [ ! -d runs/wokwi ] && [ ! -d runs ]; then
  echo "[WARN] No completed hardening run found; skipping tt_tool report printouts."
  exit 0
fi
if [[ -f tt/tt_tool.py ]]; then
  "$PY_TT" ./tt/tt_tool.py --print-warnings | tee build/tt12b/tt_print_warnings.log || true
  "$PY_TT" ./tt/tt_tool.py --print-stats | tee build/tt12b/tt_print_stats.log || true
  "$PY_TT" ./tt/tt_tool.py --print-cell-category | tee build/tt12b/tt_print_cell_category.log || true
else
  echo "[WARN] tt/tt_tool.py not found; skipping tt_tool printouts"
fi

if [[ -z "$RUN_DIR" ]]; then
  RUN_DIR="$(python3 tools/tt12b_find_run_dir.py runs build 2>/dev/null || true)"
fi

if [[ -z "$RUN_DIR" || ! -d "$RUN_DIR" ]]; then
  echo "[ERROR] Could not determine hardening run directory."
  echo "        Pass it explicitly, e.g.:"
  echo "        RUN_DIR=runs/wokwi make tt12b-after-harden"
  exit 1
fi

echo "[INFO] Run directory: $RUN_DIR"

python3 tools/tt12b_triage_reports.py "$RUN_DIR" build/tt12b/triage.md || {
  echo "[WARN] Triage found fatal/error patterns. Inspect build/tt12b/triage.md"
}

if [[ -x tools/tt12a_capture_hardening_artifact.sh ]]; then
  tools/tt12a_capture_hardening_artifact.sh "$RUN_NAME" "$RUN_DIR" | tee build/tt12b/captured_artifact_path.txt
else
  echo "[WARN] TT-12A artifact capture tool not found; skipping artifact capture."
fi

echo "[INFO] Triage summary: build/tt12b/triage.md"
