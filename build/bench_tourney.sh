#!/bin/bash
# Perf bench over Cursor-strategy-tournament round-08 leaderboard strategies.
T=examples/strategy-tournament/agents
STRATS="agent-05/round-08/s05.ms agent-01/round-08/s05.ms agent-02/round-08/s02.ms agent-01/round-08/s02.ms agent-03/round-08/s01.ms agent-05/round-08/s02.ms agent-05/round-08/s01.ms agent-06/round-08/s02.ms agent-01/round-08/s03.ms agent-01/round-08/s04.ms"
for s in $STRATS; do
  for n in "$@"; do
    out=$(node build/js/gene-runner.js --source $T/$s --synth $n --seed 42)
    bps=$(echo "$out" | sed -n 's/.*"barsPerSec":\([0-9.]*\).*/\1/p')
    ms=$(echo "$out" | sed -n 's/.*"runMs":\([0-9.]*\).*/\1/p')
    ok=$(echo "$out" | head -c 10)
    echo "$s n=$n runMs=$ms barsPerSec=$bps $ok"
  done
done
