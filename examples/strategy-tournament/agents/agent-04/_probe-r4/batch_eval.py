import json
import subprocess
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[5]
lab = root / "examples/strategy-tournament/harness/tournament_lab.py"
probe = Path(__file__).resolve().parent

sys.path.insert(0, str(root / "examples/strategy-tournament/harness"))
from tournament_lab import eval_strategy, eval_walkforward, score_entry

for f in sorted(probe.glob("*.ms")):
    if f.name.startswith("batch"):
        continue
    r = eval_strategy(f)
    wf = eval_walkforward(f)
    r["wf_mean_sharpe"] = wf
    score = score_entry(r)
    trades = sum((v.get("trades") or 0) for v in r.get("per_symbol", {}).values())
    ms = r.get("mean_sharpe") or 0
    ds = r.get("mean_d_sharpe") or 0
    mdd = r.get("median_mdd") or 0
    print(f"{f.name:12s} score={score:6.3f} mean={ms:7.3f} d={ds:+7.3f} mdd={mdd:.3f} wf={wf or 0:.3f} trades={trades}")
