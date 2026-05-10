#!/usr/bin/env bash
set -euo pipefail

NAME="${1:-}"
RUN_DIR="${2:-runs/wokwi}"

if [[ -z "$NAME" ]]; then
  echo "usage: tools/tt12a_capture_hardening_artifact.sh <name> [run-dir]" >&2
  echo "example:" >&2
  echo "  tools/tt12a_capture_hardening_artifact.sh first_harden runs/wokwi" >&2
  exit 2
fi

if [[ ! -d "$RUN_DIR" ]]; then
  echo "ERROR: run dir does not exist: $RUN_DIR" >&2
  echo "Run hardening first, or pass the actual run directory." >&2
  exit 1
fi

GIT_SHORT="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
PDK_NAME="${PDK:-unknownpdk}"
STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
DEST="artifacts/runs/${STAMP}_${GIT_SHORT}_${PDK_NAME}_${NAME}"

mkdir -p "$DEST"

# Copy a curated subset if present. Keep enough to compare GDS/layout results.
for d in final reports logs tmp objects; do
  if [[ -e "$RUN_DIR/$d" ]]; then
    cp -a "$RUN_DIR/$d" "$DEST/"
  fi
done

# Some TT/LibreLane/OpenLane runs use slightly different names/locations.
find "$RUN_DIR" -maxdepth 4 -type f \( \
  -name '*.gds' -o \
  -name '*.def' -o \
  -name '*.lef' -o \
  -name '*.mag' -o \
  -name '*.spice' -o \
  -name '*.spef' -o \
  -name '*.sdf' -o \
  -name '*.rpt' -o \
  -name '*.log' -o \
  -name 'metrics.json' -o \
  -name 'metadata.json' \
\) -print0 | while IFS= read -r -d '' f; do
  rel="${f#"$RUN_DIR"/}"
  mkdir -p "$DEST/files/$(dirname "$rel")"
  cp -a "$f" "$DEST/files/$rel"
done

python3 tools/tt12a_make_manifest.py "$DEST" "$DEST/manifest.json" >/dev/null

mkdir -p artifacts/manifests
cp "$DEST/manifest.json" "artifacts/manifests/$(basename "$DEST").json"

echo "$DEST"
