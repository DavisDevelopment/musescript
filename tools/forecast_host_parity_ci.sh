#!/usr/bin/env bash
# Initiative 2.1 — CI auto-diff: ForecastHostParityDump byte-identical on JVM vs node.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

haxe build-forecast-host-parity-node.hxml
haxe build-forecast-host-parity-jvm.hxml

node build/js/forecast-host-parity.js > /tmp/forecast-host-parity-node.txt
java -jar build/jvm/forecast-host-parity.jar > /tmp/forecast-host-parity-jvm.txt

if ! cmp -s /tmp/forecast-host-parity-node.txt /tmp/forecast-host-parity-jvm.txt; then
  echo "FORECAST HOST PARITY FAIL: JVM vs node differ" >&2
  diff -u /tmp/forecast-host-parity-node.txt /tmp/forecast-host-parity-jvm.txt | head -80 >&2
  exit 1
fi

GOLDEN="$ROOT/testdata/forecast-host-parity.golden.txt"
if [[ -f "$GOLDEN" ]]; then
  if ! cmp -s /tmp/forecast-host-parity-node.txt "$GOLDEN"; then
    echo "FORECAST HOST PARITY FAIL: node output drifted from testdata/forecast-host-parity.golden.txt" >&2
    diff -u "$GOLDEN" /tmp/forecast-host-parity-node.txt | head -80 >&2
    exit 1
  fi
fi

echo "FORECAST_HOST_PARITY_OK (jvm == node == golden)"
