#!/usr/bin/env bash
# preferVm regression soak — DetParity (cheap node golden) + MuseVm corpus/evolved
# parity + Fitness.preferVm / evaluateVm path. preferVm defaults ON.
#
# Usage:
#   bash tools/prefer_vm_soak.sh
#   bash tools/prefer_vm_soak.sh --quick          # DetParity + Fitness soak only (skip full vm-parity)
#   bash tools/prefer_vm_soak.sh --fitness-only   # prefer-vm-soak suite only
#
# See docs/ENGINE_MATRIX.md § preferVm soak.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

QUICK=0
FITNESS_ONLY=0
for a in "$@"; do
  case "$a" in
    --quick) QUICK=1 ;;
    --fitness-only) FITNESS_ONLY=1 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
  esac
done

echo "══════════════════════════════════════════════════════"
echo " preferVm soak (regression — default ON)"
echo "══════════════════════════════════════════════════════"

if [[ "$FITNESS_ONLY" -eq 0 ]]; then
  echo ""
  echo "── DetParityDump (node ↔ golden) ──"
  haxe build-det-parity-node.hxml
  node build/js/det-parity.js > /tmp/det-parity-soak.txt
  GOLDEN="$ROOT/testdata/det-parity.golden.txt"
  if ! cmp -s /tmp/det-parity-soak.txt "$GOLDEN"; then
    # Normalize newlines for environments that rewrite CRLF
    if ! diff -u <(tr -d '\r' < "$GOLDEN") <(tr -d '\r' < /tmp/det-parity-soak.txt) >/dev/null; then
      echo "DET PARITY FAIL: drifted from testdata/det-parity.golden.txt" >&2
      diff -u "$GOLDEN" /tmp/det-parity-soak.txt | head -80 >&2 || true
      exit 1
    fi
  fi
  echo "DET_PARITY_OK (node == golden)"
fi

if [[ "$FITNESS_ONLY" -eq 0 && "$QUICK" -eq 0 ]]; then
  echo ""
  echo "── vm-parity (corpus + evolved MuseVm) ──"
  node tools/engine_matrix.mjs --only vm-parity
fi

echo ""
echo "── prefer-vm-soak (Fitness.preferVm / vmParityCheck) ──"
node tools/engine_matrix.mjs --soak

echo ""
echo "PREFER_VM_SOAK_OK (preferVm default ON — Fitness-path parity green)"
