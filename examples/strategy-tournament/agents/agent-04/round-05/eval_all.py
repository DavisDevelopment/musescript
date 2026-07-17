import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[5] / "examples/strategy-tournament/harness"))
from tournament_lab import eval_strategy, eval_walkforward, score_entry

root = Path(__file__).resolve().parent
results = []
for f in sorted(root.glob("s*.ms")):
    r = eval_strategy(f)
    wf = eval_walkforward(f)
    r["wf_mean_sharpe"] = wf
    score = score_entry(r)
    trades = sum((v.get("trades") or 0) for v in r.get("per_symbol", {}).values())
    row = {
        "file": f.name,
        "score": score,
        "mean_sharpe": r.get("mean_sharpe"),
        "mean_d_sharpe": r.get("mean_d_sharpe"),
        "median_mdd": r.get("median_mdd"),
        "wf": wf,
        "trades": trades,
        "eval": r,
    }
    results.append(row)
    print(
        f"{f.name:8s} score={score:6.3f} mean={(r.get('mean_sharpe') or 0):7.3f} "
        f"d={(r.get('mean_d_sharpe') or 0):+7.3f} mdd={(r.get('median_mdd') or 0):.3f} "
        f"wf={wf or 0:.3f} trades={trades}"
    )
(root / "_eval_summary.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
