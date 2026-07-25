#!/bin/bash
# JIT-audit wrapper for musescript/evo JVM runs (EvoBench, CorpusEvoRun, EvoProof, ...).
# Standing practice: never eyeball "this run felt slower" -- run WITH the compiler telling us
# what it actually did, so a deopt storm or a rejected inline shows up in a log instead of
# just being silently eaten as lost throughput.
#
# Usage: scripts/jit_audit_run.sh <jar> <mainClass> [args...]
#   e.g. scripts/jit_audit_run.sh build/jvm/evo-bench.jar musescript.evo.graal.EvoBench --pop 40 --gens 10
#
# Writes into build/graal/jit-audit/<mainClass>_<timestamp>/:
#   deopt.log          -- deoptimization events only (-Xlog:deoptimization), kept
#   summary.txt        -- the actual answer: inline rejections + deopt counts, ranked, kept
#   compilation.xml    -- full JITWatch-compatible compile/inline log (-XX:+LogCompilation) --
#                         DELETED after summarizing by default (a representative EvoBench run
#                         produces a 1-2GB XML; nobody reads it directly, only the summary).
#                         Pass KEEP_RAW=1 to keep it (e.g. to load into JITWatch by hand).
#   stdout.log          -- the program's own output -- same DELETED-unless-KEEP_RAW=1 policy
#                         (PrintInlining floods this to tens of MB even on a short run).
#   evo_bench_report.json -- snapshot of build/graal/evo_bench_report.json (EvoBench's own
#                         wall-clock/throughput numbers) taken right after the run, if that file
#                         exists -- it's the actual timing signal, and EvoBench overwrites it on
#                         every invocation, so without this snapshot there's no way to compare
#                         throughput before/after a change once a second run has happened.
#
# NOTE: never point this at a jar another run is actively using -- see PLAN_EVO_SPEED.md's
# hard rule against rebuilding build/jvm/corpus-evo.jar mid-run. This script only READS jars,
# it never builds them, but check `wmic process where "name='java.exe'" get CommandLine` first
# if you're about to run the SAME jar a live process has open.
set -e
cd "$(dirname "$0")/.."

if [ $# -lt 2 ]; then
  echo "usage: $0 <jar> <mainClass> [args...]" >&2
  exit 1
fi

JAR="$1"; MAIN="$2"; shift 2
CP=$(cat graal/cp.txt)
TS=$(date +%Y%m%d_%H%M%S)
OUTDIR="build/graal/jit-audit/${MAIN##*.}_${TS}"
mkdir -p "$OUTDIR"

echo "=== JIT-audited run: $MAIN $* ===" >&2
echo "output dir: $OUTDIR" >&2

"$JAVA_HOME/bin/java.exe" --sun-misc-unsafe-memory-access=allow \
  -XX:+UnlockDiagnosticVMOptions \
  -XX:+LogCompilation -XX:LogFile="$OUTDIR/compilation.xml" \
  -XX:+PrintInlining \
  -Xlog:deoptimization=debug:file="$OUTDIR/deopt.log":time,uptime,level,tags \
  -cp "$CP;$JAR" "$MAIN" "$@" \
  > "$OUTDIR/stdout.log" 2>&1

{
  echo "=== JIT audit summary: $MAIN $* ==="
  echo "-- deoptimizations (top offenders by method) --"
  if [ -s "$OUTDIR/deopt.log" ]; then
    grep -oE '(deoptimization\] cid=[ ]*[0-9]+[ ]+level=[0-9]+ )[A-Za-z0-9_$.]+\.[A-Za-z0-9_$<>]+\(' "$OUTDIR/deopt.log" \
      | grep -oE '[A-Za-z0-9_$.]+\.[A-Za-z0-9_$<>]+\($' \
      | sed 's/($//' | sort | uniq -c | sort -rn | head -20
    echo "-- deopt reasons (top) --"
    grep -oE '(null_check|null_assert_or_unreached0|range_check|class_check|div0_check|unreached0|action_reinterpret|intrinsic_or_type_checked_inlining)' "$OUTDIR/deopt.log" \
      | sort | uniq -c | sort -rn
    echo "-- haxe.jvm.* / musescript.* deopt sites specifically (the ones we can actually fix) --"
    grep -E 'haxe\.jvm\.|musescript\.' "$OUTDIR/deopt.log" | grep -oE '(haxe\.jvm\.|musescript\.)[A-Za-z0-9_$.]+\([^)]*\)' | sort | uniq -c | sort -rn | head -20
  else
    echo "(none logged -- either clean, or this JDK doesn't support -Xlog:deoptimization; check stdout.log for errors)"
  fi
  echo
  echo "-- inlining rejections (top reasons) --"
  grep -oE "too large|hot method too big|not inlineable|already compiled into a big method|virtual call|receiver not constant" "$OUTDIR/compilation.xml" 2>/dev/null | sort | uniq -c | sort -rn | head -20
  echo
  echo "-- methods that got recompiled (made not entrant -- a deopt signature) --"
  n=$(grep -c "made not entrant" "$OUTDIR/compilation.xml" 2>/dev/null || true)
  echo "${n:-0}"
} > "$OUTDIR/summary.txt"

if [ "${KEEP_RAW:-0}" != "1" ]; then
  rm -f "$OUTDIR/compilation.xml" "$OUTDIR/stdout.log"
fi

if [ -f "build/graal/evo_bench_report.json" ]; then
  cp "build/graal/evo_bench_report.json" "$OUTDIR/evo_bench_report.json"
fi

echo "summary: $OUTDIR/summary.txt" >&2
cat "$OUTDIR/summary.txt" >&2
