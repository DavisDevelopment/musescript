#!/usr/bin/env bash
# Multi-CLI --seed restart matrix → SeedRobustness.verdict (CI-friendly bounded planted restarts)
set -euo pipefail
cd "$(dirname "$0")/.."

TAPE="${SEED_MATRIX_TAPE:-corpus/tapes/spy_oos_2022_2026.csv}"
SEEDS="${SEED_MATRIX_SEEDS:-42,7,99}"
POP="${SEED_MATRIX_POP:-6}"
GENS="${SEED_MATRIX_GENS:-2}"
MAXBARS="${SEED_MATRIX_MAX_BARS:-800}"

echo "Building seed-restart-matrix..."
haxe build-seed-restart-matrix.hxml

node build/js/seed-restart-matrix.js \
  --tape "$TAPE" \
  --seeds "$SEEDS" \
  --pop "$POP" \
  --gens "$GENS" \
  --max-bars "$MAXBARS" \
  --n-trials 5
