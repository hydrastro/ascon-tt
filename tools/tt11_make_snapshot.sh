#!/usr/bin/env bash
set -euo pipefail

OUT="${1:-build/ascon-tt-submission-snapshot.tar.gz}"

mkdir -p "$(dirname "$OUT")"

# Keep the snapshot source-only. Do not include build products, run outputs, or Git metadata.
tar \
  --exclude='./.git' \
  --exclude='./build' \
  --exclude='./runs' \
  --exclude='./*.vvp' \
  --exclude='./*.vcd' \
  --exclude='./*.fst' \
  --exclude='./*.zip' \
  --exclude='./*.tar.gz' \
  --exclude='./*.patch' \
  --exclude='./*.orig' \
  --exclude='./*.rej' \
  -czf "$OUT" .

echo "$OUT"
