#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(ROOT / "examples/strategy-tournament/harness"))
from tournament_lab import eval_strategy, eval_walkforward, score_entry

strats = sys.argv[1:]
if not strats:
    strats = [
        "examples/strategy-tournament/agents/agent-03/round-03/s01.ms",
        "examples/strategy-tournament/agents/agent-03/round-03/s02.ms",
        "examples/strategy-tournament/agents/agent-03/round-03/s03.ms",
        "examples/strategy-tournament/agents/agent-03/round-03/s04.ms",
        "examples/strategy-tournament/agents/agent-03/round-03/s05.ms",
        "examples/strategy-tournament/agents/agent-03/round-02/s02.ms",
        "examples/strategy-tournament/agents/agent-05/round-03/s01.ms",
    ]

for s in strats:
    p = ROOT / s if not Path(s).is_absolute() else Path(s)
    r = eval_strategy(p)
    r["wf_mean_sharpe"] = eval_walkforward(p)
    r["score"] = score_entry(r)
    print(
        f"{p.name}: score={r['score']:.3f} "
        f"sharpe={r['mean_sharpe']:.3f} d={r['mean_d_sharpe']:+.3f} "
        f"mdd={r['median_mdd']:.3f} wf={r['wf_mean_sharpe']:.3f}"
    )
