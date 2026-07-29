# Web ↔ app EquityDigest parity (CURSOR_TODO Task 1 accept).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
if [[ ! -f build/js/muse-runtime.js ]]; then
  echo "building muse-runtime.js…"
  haxe build-runtime.hxml
fi
node tools/equity_digest_web_app_parity.mjs
