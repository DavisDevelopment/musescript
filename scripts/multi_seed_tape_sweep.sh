#!/bin/bash
# Multi-seed / multi-tape validation sweep -- answers "did the evo speedups + MAP-Elites +
# risk-exits + multi-output + growth-tuner + attribution-guided crossover machinery actually
# help", which every single-run verification this session could only call "inconclusive" on.
# Same --pop/--gens config as the last full-stack verification run, varied only by seed and tape.
set -e
cd "$(dirname "$0")/.."

CP=$(cat graal/cp.txt)
JAR="build/jvm/corpus-evo.jar"
OUT="build/graal/sweep-results.tsv"
LOGDIR="build/graal/sweep-logs"
mkdir -p "$LOGDIR"

echo -e "tape\tseed\tchampion_fitness\tchampion_nodes\tniches_occupied\toos_held\toos_checked\twall_s" > "$OUT"

TAPES="nvda spy aapl"
SEEDS="42 7 123"

for tape in $TAPES; do
  for seed in $SEEDS; do
    log="$LOGDIR/${tape}_${seed}.log"
    echo "=== $tape seed=$seed ===" >&2
    "$JAVA_HOME/bin/java.exe" --sun-misc-unsafe-memory-access=allow \
      -cp "$CP;$JAR" musescript.evo.graal.CorpusEvoRun \
      --pop 40 --gens 16 --seed "$seed" --tape "data/real/${tape}.csv" \
      > "$log" 2>&1

    fitness=$(grep -oE 'CHAMPION \(fitness=[-0-9.]+' "$log" | head -1 | cut -d= -f2)
    nodes=$(grep -oE 'nodeCount=[0-9]+' "$log" | head -1 | cut -d= -f2)
    niches=$(grep -oE 'MAP-Elites diversity: [0-9]+' "$log" | head -1 | grep -oE '[0-9]+$')
    oosline=$(grep -oE 'OOS summary: [0-9]+/[0-9]+' "$log" | head -1 | grep -oE '[0-9]+/[0-9]+')
    held=$(echo "$oosline" | cut -d/ -f1)
    checked=$(echo "$oosline" | cut -d/ -f2)
    wall=$(grep -oE 'total wall: [0-9.]+' "$log" | head -1 | grep -oE '[0-9.]+$')

    echo -e "${tape}\t${seed}\t${fitness}\t${nodes}\t${niches}\t${held}\t${checked}\t${wall}" >> "$OUT"
    echo "  fitness=$fitness nodes=$nodes niches=$niches oos=${held}/${checked} wall=${wall}s" >&2
  done
done

echo "=== SWEEP DONE ===" >&2
cat "$OUT" >&2
