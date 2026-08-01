#!/usr/bin/env bash
# Bounded multi-gen planted co-evo on a real tape → hardened OOS GO/NO-GO
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${PLANTED_TAPE:-}" ]]; then
  TAPE="$PLANTED_TAPE"
elif [[ -f data/real/tsla.csv ]]; then
  TAPE="data/real/tsla.csv"
else
  TAPE="corpus/tapes/spy_oos_2022_2026.csv"
fi
SEED="${PLANTED_SEED:-42}"
POP="${PLANTED_POP:-8}"
GENS="${PLANTED_GENS:-4}"
MAXBARS="${PLANTED_MAX_BARS:-1200}"

echo "Building planted-coevo (tape=$TAPE)..."
haxe build-planted-coevo.hxml

node build/js/planted-coevo.js \
  --tape "$TAPE" \
  --seed "$SEED" \
  --pop "$POP" \
  --gens "$GENS" \
  --max-bars "$MAXBARS" \
  --n-trials 5 \
  --prereg \
  --prereg-threshold 0
