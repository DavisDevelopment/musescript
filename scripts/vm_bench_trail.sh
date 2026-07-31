#!/bin/bash
# VM performance trail capture (BYTECODE_VM_TODO.md) — appends one row to VM_PERF_TRAIL.md with
# per-eval speed (JVM + JS) AND evo champion quality, at the current checkpoint.
#
# Usage:  bash scripts/vm_bench_trail.sh "P1.1 unboxed stack"
#         SKIP_BUILD=1 bash scripts/vm_bench_trail.sh "..."   # reuse current jar/js (faster)
#
# HARD RULE: do NOT run while a corpus-evo run is alive elsewhere (rebuild lazy-loads classes).
set -e
cd "$(dirname "$0")/.."
LABEL="${1:-checkpoint}"
SHA=$(git rev-parse --short HEAD)
DATE=$(date -u +%Y-%m-%d)
CP=$(cat graal/cp.txt)
JAVA="${JAVA_HOME:+$JAVA_HOME/bin/}java"
RUN() { "$JAVA" --sun-misc-unsafe-memory-access=allow -cp "$CP;build/jvm/corpus-evo.jar" musescript.evo.graal.CorpusEvoRun "$@"; }

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  echo "[trail] building jar + js bench..."
  haxe build-corpus-evo.hxml >/dev/null 2>&1
  haxe build-vm-bench-js.hxml >/dev/null 2>&1
fi

echo "[trail] JVM per-eval..."
JVMB=$(RUN --pop 20 --gens 1 --seed 42 --tape data/real/nvda.csv --vm-bench 2>&1)
JVM_SPD=$(echo "$JVMB" | grep -oE 'SPEEDUP *= *[0-9.]+x' | grep -oE '[0-9.]+x')
JVM_I=$(echo "$JVMB" | grep 'interp(' | grep -oE '[0-9.]+ ms' | grep -oE '[0-9.]+')
JVM_V=$(echo "$JVMB" | grep 'vm(' | grep -oE '[0-9.]+ ms' | grep -oE '[0-9.]+')

echo "[trail] JS per-eval..."
JSB=$(node build/js/vm-bench.js 2>&1)
JS_SMA=$(echo "$JSB" | grep 'sma-cross' | grep -oE 'speedup=[0-9.]+x' | grep -oE '[0-9.]+x')
JS_ARI=$(echo "$JSB" | grep 'arith-heavy' | grep -oE 'speedup=[0-9.]+x' | grep -oE '[0-9.]+x')

echo "[trail] evo champion (pop=80 gens=20 --vm)..."
EVO=$(RUN --pop 80 --gens 20 --seed 42 --tape data/real/nvda.csv --vm 2>&1)
CHAMP=$(echo "$EVO" | grep -oE 'champion="[^"]*"' | tail -1 | sed 's/champion=//; s/"//g')
OOS=$(echo "$EVO" | grep 'champion-oos] metric' | head -1 | grep -oE 'metric=[-0-9.]+' | cut -d= -f2)
HOLD=$(echo "$EVO" | grep 'OOS summary:' | grep -oE '[0-9]+/[0-9]+' | head -1)
VERD=$(echo "$EVO" | grep 'seed-median' | grep -oE '=> (GO|NO-GO)' | grep -oE 'GO|NO-GO')
PBO=$(echo "$EVO" | grep 'rigor PBO' | grep -oE 'PBO=[0-9.]+' | cut -d= -f2)

ROW="| $DATE | \`$SHA\` | $LABEL | ${JVM_SPD} (${JVM_I}→${JVM_V}ms) | ${JS_SMA} / ${JS_ARI} | ${CHAMP} · OOS ${OOS} · hold ${HOLD} · ${VERD} · PBO ${PBO} |"
printf "%b\n" "$ROW" >> VM_PERF_TRAIL.md
echo ""
echo "[trail] appended to VM_PERF_TRAIL.md:"
printf "%b\n" "$ROW"