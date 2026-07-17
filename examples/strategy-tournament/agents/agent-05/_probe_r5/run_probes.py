import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
LAB = ROOT / "examples/strategy-tournament/harness/tournament_lab.py"
PROBE = Path(__file__).resolve().parent
TAPES = ROOT / "examples/strategy-tournament/tapes"
RUNNER = ROOT / "build/js/gene-runner.js"
WF = [("2019-01-02", "2019-04-01"), ("2022-01-03", "2022-04-01"), ("2024-10-01", "2024-12-31")]
WF_SYMS = ["SPY", "QQQ", "AAPL"]


def wf_sharpe(path):
    sharpes = []
    for i, (ws, we) in enumerate(WF):
        for sym in WF_SYMS:
            tape = TAPES / f"wf_{i+1}_{sym}_{ws}_{we}.csv"
            if tape.exists():
                d = json.loads(subprocess.check_output(
                    ["node", str(RUNNER), "--source", str(path), "--tape", str(tape), "--target", "js", "--symbol", sym],
                    cwd=str(ROOT), text=True).strip().splitlines()[-1])
                if d.get("ok"):
                    sharpes.append(float(d["sharpe"]))
    return sum(sharpes) / len(sharpes) if sharpes else 0


def full_score(r, wf):
    return 0.40*(r.get("mean_sharpe") or 0)+0.25*(r.get("mean_d_sharpe") or 0)+0.20*(1-min(r.get("median_mdd") or 1,1))+0.15*wf


results = []
for p in sorted(PROBE.glob("p*.ms")):
    r = json.loads(subprocess.check_output([sys.executable, str(LAB), "--eval", str(p)], text=True))
    wf = wf_sharpe(p)
    sc = full_score(r, wf)
    results.append({"file": p.name, "eval": r, "wf": wf, "score": sc})

for row in sorted(results, key=lambda x: x["score"], reverse=True):
    r = row["eval"]
    print(f"{row['file']}: score={row['score']:.3f} sharpe={r['mean_sharpe']:.3f} d={r['mean_d_sharpe']:+.3f} mdd={r['median_mdd']:.3f} wf={row['wf']:.3f}")

(PROBE / "_summary.json").write_text(json.dumps(results, indent=2))
