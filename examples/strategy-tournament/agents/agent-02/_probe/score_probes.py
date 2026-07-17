import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
sys.path.insert(0, str(ROOT / "examples/strategy-tournament/harness"))
from tournament_lab import eval_strategy, eval_walkforward, score_entry

probe_dir = Path(__file__).parent
refs = [
    ROOT / "examples/strategy-tournament/agents/agent-05/round-03/s01.ms",
    ROOT / "examples/strategy-tournament/agents/agent-02/round-03/s04.ms",
    ROOT / "examples/strategy-tournament/agents/agent-06/round-03/s03.ms",
    ROOT / "examples/strategy-tournament/agents/agent-03/round-03/s01.ms",
]
paths = sorted(probe_dir.glob("*.ms")) + refs
rows = []
for p in paths:
    r = eval_strategy(p)
    wf = eval_walkforward(p)
    r["wf_mean_sharpe"] = wf
    r["score"] = score_entry(r)
    r["path"] = p.name if p.parent.name == "_probe" else f"REF/{p.parent.parent.name}/{p.name}"
    rows.append(r)
rows.sort(key=lambda x: x["score"], reverse=True)
print(f"{'name':45} score  sharpe  d_sh   mdd    wf")
for r in rows:
    ms = r.get("mean_sharpe") or 0
    ds = r.get("mean_d_sharpe") or 0
    mdd = r.get("median_mdd") or 0
    wf = r.get("wf_mean_sharpe") or 0
    print(f"{r['path']:45} {r['score']:.3f}  {ms:.3f}  {ds:+.3f}  {mdd:.3f}  {wf:.3f}")
