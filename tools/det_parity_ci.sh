#!/usr/bin/env bash
# Bucket D4 — CI auto-diff: DetParityDump must be byte-identical on JVM vs node.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

haxe build-det-parity-node.hxml
haxe build-det-parity-jvm.hxml

node build/js/det-parity.js > /tmp/det-parity-node.txt
java -jar build/jvm/det-parity.jar > /tmp/det-parity-jvm.txt

if ! cmp -s /tmp/det-parity-node.txt /tmp/det-parity-jvm.txt; then
  echo "DET PARITY FAIL: JVM vs node differ" >&2
  diff -u /tmp/det-parity-node.txt /tmp/det-parity-jvm.txt | head -80 >&2
  exit 1
fi

GOLDEN="$ROOT/testdata/det-parity.golden.txt"
if [[ -f "$GOLDEN" ]]; then
  if ! cmp -s /tmp/det-parity-node.txt "$GOLDEN"; then
    echo "DET PARITY FAIL: node output drifted from testdata/det-parity.golden.txt" >&2
    diff -u "$GOLDEN" /tmp/det-parity-node.txt | head -80 >&2
    exit 1
  fi
fi

echo "DET_PARITY_OK (jvm == node == golden)"
