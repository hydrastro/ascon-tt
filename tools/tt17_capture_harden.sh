#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  tt17_capture_harden.sh \
    --tiles 4x2 \
    --clock-hz 10000000 \
    --store min-area \
    --name shared_4x2_10mhz \
    [--branch min-area] [--allow-dirty] [--force] \
    [--dvc-remote REMOTE] [--push] [--skip-harden]

Captures config, logs, GDS/DEF candidates, optional KLayout screenshot,
manifest/checksums, and optional DVC add/push.
USAGE
}

tiles=""
clock_hz=""
store="default"
name=""
branch=""
allow_dirty=0
force=0
dvc_remote=""
push=0
skip_harden=0

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tiles) tiles="$2"; shift 2 ;;
    --clock-hz) clock_hz="$2"; shift 2 ;;
    --store|--store-name) store="$2"; shift 2 ;;
    --name) name="$2"; shift 2 ;;
    --branch) branch="$2"; shift 2 ;;
    --allow-dirty) allow_dirty=1; shift ;;
    --force) force=1; shift ;;
    --dvc-remote) dvc_remote="$2"; shift 2 ;;
    --push|--dvc-push) push=1; shift ;;
    --skip-harden) skip_harden=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg $1" >&2; usage; exit 1 ;;
  esac
done

if [ -z "$tiles" ] || [ -z "$clock_hz" ] || [ -z "$name" ]; then
  usage
  exit 1
fi

if [ ! -f info.yaml ] || [ ! -f Makefile ] || [ ! -d src ]; then
  echo "ERROR: run from ascon-tt repo root" >&2
  exit 1
fi

if [ -n "$branch" ]; then
  cur="$(git branch --show-current 2>/dev/null || true)"
  if [ "$cur" != "$branch" ]; then
    echo "ERROR: current branch '$cur' != requested '$branch'" >&2
    exit 1
  fi
fi

if [ "$allow_dirty" -eq 0 ] && [ -n "$(git status --porcelain)" ]; then
  echo "ERROR: working tree dirty. Commit/stash first, or use --allow-dirty." >&2
  git status --short >&2
  exit 1
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
git_sha="$(git rev-parse --short HEAD 2>/dev/null || echo unknown)"
git_branch="$(git branch --show-current 2>/dev/null || echo unknown)"
artifact="artifacts/hardening/$store/$name"

if [ -e "$artifact" ] && [ "$force" -eq 0 ]; then
  echo "ERROR: artifact exists: $artifact"
  echo "Use --force or another --name."
  exit 1
fi

rm -rf "$artifact"
mkdir -p "$artifact"/{config,logs,layout,screenshots,reports}

info_bak="$(mktemp)"
cfg_bak="$(mktemp)"
cp info.yaml "$info_bak"
[ -f src/config.json ] && cp src/config.json "$cfg_bak" || : > "$cfg_bak"

restore_config() {
  cp "$info_bak" info.yaml
  [ -s "$cfg_bak" ] && cp "$cfg_bak" src/config.json || true
}
trap restore_config EXIT

cp info.yaml "$artifact/config/info.before.yaml"
[ -f src/config.json ] && cp src/config.json "$artifact/config/config.before.json" || true
git status --short > "$artifact/reports/git_status_short.txt"
git diff > "$artifact/reports/git_diff.patch" || true

cat > "$artifact/README.md" <<EOF
# Hardening artifact: $name

- timestamp_utc: $ts
- branch: $git_branch
- git_sha: $git_sha
- tiles: $tiles
- clock_hz: $clock_hz
- store: $store
- dvc_remote: ${dvc_remote:-none}
EOF

echo "[TT17] set config tiles=$tiles clock_hz=$clock_hz"
python3 tools/tt15_set_tt_config.py --tiles "$tiles" --clock-hz "$clock_hz" | tee "$artifact/logs/set_config.log"
cp info.yaml "$artifact/config/info.used.yaml"
[ -f src/config.json ] && cp src/config.json "$artifact/config/config.used.json" || true

cfg_rc=0
harden_rc=0

if [ "$skip_harden" -eq 0 ]; then
  echo "[TT17] make tt12-create-user-config"
  set +e
  make tt12-create-user-config > "$artifact/logs/create_user_config.log" 2>&1
  cfg_rc=$?
  set -e

  echo "[TT17] make tt12-harden"
  set +e
  make tt12-harden > "$artifact/logs/harden.log" 2>&1
  harden_rc=$?
  set -e
else
  echo "[TT17] skip harden" > "$artifact/logs/harden.log"
fi

{
  echo "# Hardening summary"
  echo
  echo "- create_user_config_rc: $cfg_rc"
  echo "- harden_rc: $harden_rc"
  echo
  echo "## Key hardening lines"
  echo '```text'
  grep -E "GPL-|Utilization|Region area|Fixed instances area|Movable instances area|Standard cells area|ERROR|failed|violation|wns|tns" "$artifact/logs/harden.log" 2>/dev/null | tail -220 || true
  echo '```'
} > "$artifact/reports/harden_summary.md"

# Candidate layout files by recency.
find runs build -type f \( -name '*.gds' -o -name '*.gds.gz' -o -name '*.def' -o -name '*.def.gz' -o -name '*.lef' -o -name '*.spice' -o -name '*.nl.v' \) -printf '%T@ %p\n' 2>/dev/null \
  | sort -n > "$artifact/reports/layout_candidates_timestamped.txt" || true

find runs build -type f \( -name '*.gds' -o -name '*.gds.gz' \) -printf '%T@ %p\n' 2>/dev/null \
  | sort -n | tail -5 | awk '{ $1=""; sub(/^ /,""); print }' > "$artifact/reports/gds_candidates.txt" || true

while read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && cp "$f" "$artifact/layout/" || true
done < "$artifact/reports/gds_candidates.txt"

find runs build -type f \( -name '*.def' -o -name '*.def.gz' \) -printf '%T@ %p\n' 2>/dev/null \
  | sort -n | tail -5 | awk '{ $1=""; sub(/^ /,""); print }' > "$artifact/reports/def_candidates.txt" || true

while read -r f; do
  [ -n "$f" ] && [ -f "$f" ] && cp "$f" "$artifact/layout/" || true
done < "$artifact/reports/def_candidates.txt"

latest_gds="$(find "$artifact/layout" -type f \( -name '*.gds' -o -name '*.gds.gz' \) | sort | tail -1 || true)"
if [ -n "$latest_gds" ]; then
  echo "$latest_gds" > "$artifact/layout/latest_gds.txt"
  if command -v klayout >/dev/null 2>&1 && [[ "$latest_gds" != *.gz ]] && [ -f tools/tt17_klayout_screenshot.py ]; then
    set +e
    klayout -z -r tools/tt17_klayout_screenshot.py -rd "in_gds=$latest_gds" -rd "out_png=$artifact/screenshots/klayout.png" \
      > "$artifact/logs/klayout_screenshot.log" 2>&1
    echo "$?" > "$artifact/logs/klayout_screenshot.rc"
    set -e
  fi
else
  echo "No GDS found; hardening may not have reached final export." > "$artifact/layout/NO_GDS_FOUND.txt"
fi

# Manifest/checksums.
{
  echo "# Artifact manifest"
  echo
  echo "- timestamp_utc: \`$ts\`"
  echo "- branch: \`$git_branch\`"
  echo "- git_sha: \`$git_sha\`"
  echo "- tiles: \`$tiles\`"
  echo "- clock_hz: \`$clock_hz\`"
  echo "- harden_rc: \`$harden_rc\`"
  echo
  echo "| file | sha256 | bytes |"
  echo "|---|---|---:|"
  find "$artifact" -type f ! -name manifest.md -print | sort | while read -r f; do
    sum="$(sha256sum "$f" | awk '{print $1}')"
    size="$(wc -c < "$f" | tr -d ' ')"
    rel="${f#$artifact/}"
    echo "| \`$rel\` | \`$sum\` | $size |"
  done
} > "$artifact/manifest.md"

if command -v dvc >/dev/null 2>&1; then
  echo "[TT17] dvc add $artifact"
  dvc add "$artifact" > "$artifact.dvc.add.log" 2>&1 || {
    echo "DVC add failed; see $artifact.dvc.add.log" >&2
  }
  if [ "$push" -eq 1 ]; then
    if [ -n "$dvc_remote" ]; then
      dvc push -r "$dvc_remote" > "$artifact.dvc.push.log" 2>&1
    else
      dvc push > "$artifact.dvc.push.log" 2>&1
    fi
  fi
else
  echo "DVC not found; skipped dvc add." > "$artifact/DVC_SKIPPED.txt"
fi

echo
echo "[TT17] captured: $artifact"
echo "  $artifact/manifest.md"
echo "  $artifact/reports/harden_summary.md"
echo "  $artifact/layout/"
echo "  $artifact/screenshots/"
echo

exit "$harden_rc"
