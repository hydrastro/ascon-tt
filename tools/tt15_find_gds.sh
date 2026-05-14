#!/usr/bin/env bash
set -euo pipefail

echo "GDS candidates:"
find runs build artifacts -type f \( -name '*.gds' -o -name '*.gds.gz' \) -print 2>/dev/null | sort || true

echo
echo "DEF candidates:"
find runs build artifacts -type f \( -name '*.def' -o -name '*.def.gz' \) -print 2>/dev/null | sort | tail -40 || true

echo
echo "KLayout/Magic candidates:"
find runs build artifacts -type f \( -name '*.mag' -o -name '*.lef' -o -name '*.spice' \) -print 2>/dev/null | sort | tail -80 || true
