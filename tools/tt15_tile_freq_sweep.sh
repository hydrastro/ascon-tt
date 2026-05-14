#!/usr/bin/env bash
set -euo pipefail

TILES_LIST="${TT_SWEEP_TILES:-6x2 4x2 8x2}"
FREQ_LIST="${TT_SWEEP_FREQS:-10000000 25000000 5000000}"
RUN_ROOT="${TT_SWEEP_RUN_ROOT:-artifacts/runs/tt15_sweep_$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "$RUN_ROOT" build/tt15

INFO_BAK="$(mktemp)"
CONFIG_BAK="$(mktemp)"
cp info.yaml "$INFO_BAK"
if [ -f src/config.json ]; then
  cp src/config.json "$CONFIG_BAK"
else
  : > "$CONFIG_BAK"
fi

restore() {
  cp "$INFO_BAK" info.yaml
  if [ -s "$CONFIG_BAK" ]; then
    cp "$CONFIG_BAK" src/config.json
  fi
}
trap restore EXIT

summary="$RUN_ROOT/summary.md"
: > "$summary"

{
  echo "# TT-15 tile/frequency sweep"
  echo
  echo "- git: $(git branch --show-current 2>/dev/null) $(git rev-parse --short HEAD 2>/dev/null)"
  echo "- run_root: \`$RUN_ROOT\`"
  echo "- tiles: \`$TILES_LIST\`"
  echo "- freqs: \`$FREQ_LIST\`"
  echo
  echo "| tiles | clock_hz | harden rc | verdict | run dir |"
  echo "|---|---:|---:|---|---|"
} >> "$summary"

for tiles in $TILES_LIST; do
  for freq in $FREQ_LIST; do
    tag="${tiles}_${freq}"
    tag="${tag//x/X}"
    out="$RUN_ROOT/$tag"
    mkdir -p "$out"

    echo "== TT-15 sweep tiles=$tiles clock_hz=$freq =="
    python3 tools/tt15_set_tt_config.py --tiles "$tiles" --clock-hz "$freq" | tee "$out/config_set.log"

    make tt12-write-user-config > "$out/create_user_config.log" 2>&1 || true

    set +e
    make tt12-harden > "$out/harden.log" 2>&1
    rc=$?
    set -e

    verdict="unknown"
    if grep -q "GPL-0301" "$out/harden.log"; then
      verdict="area_overflow"
    elif grep -qi "timing" "$out/harden.log" && grep -qi "viol" "$out/harden.log"; then
      verdict="timing_issue"
    elif grep -qi "failed" "$out/harden.log"; then
      verdict="failed"
    elif grep -qi "error" "$out/harden.log"; then
      verdict="error"
    elif [ "$rc" -eq 0 ]; then
      verdict="harden_passed"
    else
      verdict="rc_$rc"
    fi

    {
      echo "# Sweep run $tag"
      echo
      echo "- tiles: $tiles"
      echo "- clock_hz: $freq"
      echo "- rc: $rc"
      echo "- verdict: $verdict"
      echo
      echo "## GPL/utilization/timing lines"
      echo '```text'
      grep -E "GPL-|Utilization|Region area|Movable instances area|Standard cells area|setup|hold|violation|violated|wns|tns" "$out/harden.log" | tail -120 || true
      echo '```'
      echo
      echo "## GDS/DEF candidates after run"
      echo '```text'
      tools/tt15_find_gds.sh || true
      echo '```'
    } > "$out/report.md"

    printf "| %s | %s | %s | %s | \`%s\` |\n" "$tiles" "$freq" "$rc" "$verdict" "$out" >> "$summary"

    find runs -type f \( -name '*.gds' -o -name '*.gds.gz' -o -name '*.def' -o -name '*.def.gz' \) -print 2>/dev/null \
      | sort | tail -20 > "$out/layout_files.txt" || true
  done
done

echo
echo "Sweep complete:"
echo "  $summary"
echo
cat "$summary"
