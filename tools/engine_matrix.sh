#!/usr/bin/env bash
# Engine-matrix honesty gate (bash wrapper → node tools/engine_matrix.mjs)
set -euo pipefail
cd "$(dirname "$0")/.."
exec node tools/engine_matrix.mjs "$@"
