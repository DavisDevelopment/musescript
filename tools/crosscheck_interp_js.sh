#!/bin/bash
# Interp-vs-JS backend metrics cross-check on tournament round-08 strategies.
# Since the CallsiteIds pass (2026-07-17), stateful builtins
# (crossover/crossunder/rising/falling) are keyed by STATIC callsite id in
# both backends, so all 10 strategies must MATCH. Any DIVERGE line is a
# regression. (Historical: pre-CallsiteIds, per-bar call-order slots aliased
# under short-circuit skipping and agent-01/round-08/s02.ms diverged.)
T=examples/strategy-tournament/agents
TP=examples/strategy-tournament/tapes
STRIP='s/"runMs":[0-9.]*,//;s/"barsPerSec":[0-9.]*,//;s/"backend":"[a-z]*",//;s/"emitted":[a-z]*,//;s/,"fallback":true//'
for s in agent-05/round-08/s05.ms agent-01/round-08/s05.ms agent-02/round-08/s02.ms agent-01/round-08/s02.ms agent-03/round-08/s01.ms agent-05/round-08/s02.ms agent-05/round-08/s01.ms agent-06/round-08/s02.ms agent-01/round-08/s03.ms agent-01/round-08/s04.ms; do
  j=$(node build/js/gene-runner.js --source $T/$s --tape $TP/eval_3m_SPY.csv --target js 2>/dev/null | tail -1 | sed "$STRIP")
  i=$(node build/js/gene-runner.js --source $T/$s --tape $TP/eval_3m_SPY.csv --target native 2>/dev/null | tail -1 | sed "$STRIP")
  [ "$j" == "$i" ] && echo "MATCH    $s" || echo "DIVERGE  $s"
done
