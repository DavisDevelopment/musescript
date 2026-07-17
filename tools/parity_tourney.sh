#!/bin/bash
T=examples/strategy-tournament/agents
TP=examples/strategy-tournament/tapes
STRATS="agent-05/round-08/s05.ms agent-01/round-08/s05.ms agent-02/round-08/s02.ms agent-01/round-08/s02.ms agent-03/round-08/s01.ms agent-05/round-08/s02.ms agent-05/round-08/s01.ms agent-06/round-08/s02.ms agent-01/round-08/s03.ms agent-01/round-08/s04.ms"
TAPES="eval_3m_SPY.csv eval_3m_QQQ.csv eval_3m_NVDA.csv eval_3m_AMD.csv wf_2_SPY_2022-01-03_2022-04-01.csv"
for s in $STRATS; do
  for t in $TAPES; do
    out=$(node build/js/gene-runner.js --source $T/$s --tape $TP/$t)
    clean=$(echo "$out" | sed 's/"runMs":[0-9.]*,//;s/"barsPerSec":[0-9.]*,//')
    echo "$s|$t|$clean"
  done
  # long synthetic tape parity too
  out=$(node build/js/gene-runner.js --source $T/$s --synth 10000 --seed 42)
  clean=$(echo "$out" | sed 's/"runMs":[0-9.]*,//;s/"barsPerSec":[0-9.]*,//')
  echo "$s|synth10k|$clean"
done
