#!/usr/bin/env bash
set -uo pipefail

REPO="${1:-$(pwd)}"
cd "$REPO" || exit 1

OUT="build/tt14d_smoke"
ASCON_RTL_WORKTREE="${ASCON_RTL_WORKTREE:-../ascon-rtl}"

mkdir -p "$OUT"
SUMMARY="$OUT/summary.md"
: > "$SUMMARY"

say() {
  mkdir -p "$OUT"
  printf '%s\n' "$*"
  printf '%s\n' "$*" >> "$SUMMARY"
}

run_cmd() {
  local name="$1"
  shift
  mkdir -p "$OUT"
  local log="$OUT/${name}.log"

  say ""
  say "## $name"
  say ""
  say '```sh'
  say "$*"
  say '```'

  echo "===== $name ====="
  echo "$*" | tee "$log"

  "$@" >>"$log" 2>&1
  local rc=$?

  mkdir -p "$OUT"
  if [ ! -f "$SUMMARY" ]; then
    : > "$SUMMARY"
    say "# TT-14D min-area smoke report"
    say ""
    say "**NOTE:** summary file was recreated after a command removed build/."
  fi

  if [ "$rc" -eq 0 ]; then
    say ""
    say "**PASS**"
  else
    say ""
    say "**FAIL rc=$rc**"
    say ""
    say "Last 80 log lines:"
    say ""
    say '```text'
    if [ -f "$log" ]; then
      tail -80 "$log" >> "$SUMMARY"
    else
      echo "missing log file: $log" >> "$SUMMARY"
    fi
    say '```'
  fi

  return "$rc"
}

target_exists() {
  make -qp 2>/dev/null | awk -F: '/^[A-Za-z0-9_.-]+:/ {print $1}' | grep -qx "$1"
}

say "# TT-14D min-area smoke report"
say ""
say "\`date -u\`: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
say "\`pwd\`: $(pwd)"
say "\`git\`: $(git branch --show-current 2>/dev/null) $(git rev-parse --short HEAD 2>/dev/null)"
say ""
say "ASCON_RTL_WORKTREE=$ASCON_RTL_WORKTREE"

run_cmd "00_git_status" git status --short

# Run clean and sanity separately so build/tt14d_smoke can be recreated after clean.
run_cmd "01_clean" make clean
CLEAN_RC=$?
mkdir -p "$OUT"
[ -f "$SUMMARY" ] || : > "$SUMMARY"

run_cmd "02_sanity" make sanity
SANITY_RC=$?

run_cmd "03_lint" make lint
LINT_RC=$?

if [ ! -d "$ASCON_RTL_WORKTREE" ]; then
  say ""
  say "## vector_dependency"
  say ""
  say "**FAIL**: ASCON_RTL_WORKTREE does not exist: \`$ASCON_RTL_WORKTREE\`"
  VECDEP_RC=1
elif [ ! -d "$ASCON_RTL_WORKTREE/external/ascon-c" ]; then
  say ""
  say "## vector_dependency"
  say ""
  say "**FAIL**: missing \`$ASCON_RTL_WORKTREE/external/ascon-c\`."
  say ""
  say "Fix in sibling ascon-rtl:"
  say ""
  say '```sh'
  say "git -C $ASCON_RTL_WORKTREE clone https://github.com/ascon/ascon-c external/ascon-c"
  say "# or track it:"
  say "git -C $ASCON_RTL_WORKTREE submodule add https://github.com/ascon/ascon-c external/ascon-c"
  say "git -C $ASCON_RTL_WORKTREE commit -m 'Add ascon-c vector generator dependency'"
  say '```'
  VECDEP_RC=1
else
  say ""
  say "## vector_dependency"
  say ""
  say "**PASS**: found \`$ASCON_RTL_WORKTREE/external/ascon-c\`."
  VECDEP_RC=0
fi

if [ "$VECDEP_RC" -eq 0 ]; then
  run_cmd "04_sim_old_prod_directout" make sim-aead-vectors-prod-directout ASCON_RTL_WORKTREE="$ASCON_RTL_WORKTREE"
  OLD_SIM_RC=$?

  run_cmd "05_sim_shared_prod_directout" make sim-aead-vectors-shared-prod-directout ASCON_RTL_WORKTREE="$ASCON_RTL_WORKTREE"
  SHARED_SIM_RC=$?
else
  OLD_SIM_RC=99
  SHARED_SIM_RC=99
fi

if target_exists synth-prod-aead-top-directout; then
  run_cmd "06_synth_old_prod_directout" make synth-prod-aead-top-directout
  OLD_SYNTH_RC=$?
else
  say ""
  say "## 06_synth_old_prod_directout"
  say ""
  say "**SKIP**: target \`synth-prod-aead-top-directout\` not found."
  OLD_SYNTH_RC=98
fi

if target_exists synth-prod-aead-shared-directout; then
  run_cmd "07_synth_shared_prod_directout" make synth-prod-aead-shared-directout
  SHARED_SYNTH_RC=$?
else
  say ""
  say "## 07_synth_shared_prod_directout"
  say ""
  say "**SKIP**: target \`synth-prod-aead-shared-directout\` not found."
  SHARED_SYNTH_RC=98
fi

if [ -f tools/report_tt5_profiles.py ]; then
  PROFILE_ARGS=()
  [ -f build/yosys_tt_prod_aead_top_directout_stat.txt ] && PROFILE_ARGS+=(build/yosys_tt_prod_aead_top_directout_stat.txt)
  [ -f build/yosys_tt_prod_aead_shared_directout_stat.txt ] && PROFILE_ARGS+=(build/yosys_tt_prod_aead_shared_directout_stat.txt)
  if [ "${#PROFILE_ARGS[@]}" -gt 0 ]; then
    run_cmd "08_area_compare" python3 tools/report_tt5_profiles.py "${PROFILE_ARGS[@]}"
  fi
fi

say ""
say "# Summary"
say ""
say "| check | rc |"
say "|---|---:|"
say "| clean | $CLEAN_RC |"
say "| sanity | $SANITY_RC |"
say "| lint | $LINT_RC |"
say "| vector dependency | $VECDEP_RC |"
say "| old prod directout sim | $OLD_SIM_RC |"
say "| shared prod directout sim | $SHARED_SIM_RC |"
say "| old prod directout synth | $OLD_SYNTH_RC |"
say "| shared prod directout synth | $SHARED_SYNTH_RC |"
say ""
say "Report written to: \`$SUMMARY\`"

echo
echo "TT-14D smoke complete."
echo "Report: $SUMMARY"
echo "Run:"
echo "  sed -n '1,320p' $SUMMARY"

# For min-area bring-up, shared sim may fail; old path/sanity/lint must not.
if [ "$SANITY_RC" -ne 0 ] || [ "$LINT_RC" -ne 0 ] || [ "$OLD_SIM_RC" -ne 0 ]; then
  exit 1
fi

exit 0
