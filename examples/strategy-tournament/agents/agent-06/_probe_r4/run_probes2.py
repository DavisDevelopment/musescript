import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
LAB = ROOT / "examples/strategy-tournament/harness/tournament_lab.py"
PROBE = Path(__file__).resolve().parent
TAPES = ROOT / "examples/strategy-tournament/tapes"

probes = {
    "macd_exit": """strategy MacdExit {
  onBar { m = macd(close, 8, 21, 5)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "macd_mom": """strategy MacdMom {
  onBar { m = macd(close, 8, 21, 5)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || (m.hist < 0 && mom(8) < 0): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "macd_ema21": """strategy MacdEma {
  onBar { m = macd(close, 8, 21, 5); t = ema(close, 21)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0 || close < t: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "macd_layered": """strategy MacdLayer {
  onBar { m = macd(close, 8, 21, 5)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0: flat() }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < ema(close, 8): flat()
  }
}""",
    "don13_entry": """strategy Don13 {
  onBar { when high >= highest(high, 13): long(); when low <= lowest(low, 8): flat() }
  onPosition { when bars_in_trade >= 8: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "don21_8exit": """strategy Don21x8 {
  onBar { when high >= highest(high, 21): long(); when low <= lowest(low, 8): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "macd134": """strategy Macd134 {
  onBar { m = macd(close, 13, 34, 8)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "dual_or": """strategy DualOr {
  onBar { e8 = ema(close, 8); e34 = ema(close, 34)
    when (high >= highest(high, 21)) || (e8 > e34 && high >= highest(high, 13)): long()
    when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
}

WF = [
    ("2019-01-02", "2019-04-01"),
    ("2022-01-03", "2022-04-01"),
    ("2024-10-01", "2024-12-31"),
]
WF_SYMS = ["SPY", "QQQ", "AAPL"]
RUNNER = ROOT / "build/js/gene-runner.js"


def run_bt(path, tape, sym=""):
    cmd = ["node", str(RUNNER), "--source", str(path), "--tape", str(tape), "--target", "js"]
    if sym:
        cmd.extend(["--symbol", sym])
    out = subprocess.check_output(cmd, cwd=str(ROOT), text=True)
    return json.loads(out.strip().splitlines()[-1])


def wf_sharpe(path):
    sharpes = []
    for i, (ws, we) in enumerate(WF):
        for sym in WF_SYMS:
            tape = TAPES / f"wf_{i+1}_{sym}_{ws}_{we}.csv"
            if tape.exists():
                d = run_bt(path, tape, sym)
                if d.get("ok"):
                    sharpes.append(float(d["sharpe"]))
    return sum(sharpes) / len(sharpes) if sharpes else 0


def full_score(r, wf):
    ms = r.get("mean_sharpe") or 0
    ds = r.get("mean_d_sharpe") or 0
    mdd = r.get("median_mdd") or 1
    return 0.40 * ms + 0.25 * ds + 0.20 * (1 - min(mdd, 1)) + 0.15 * wf


for name, src in probes.items():
    (PROBE / f"{name}.ms").write_text(src)

for name in probes:
    p = PROBE / f"{name}.ms"
    out = subprocess.check_output([sys.executable, str(LAB), "--eval", str(p)], text=True)
    r = json.loads(out)
    wf = wf_sharpe(p)
    sc = full_score(r, wf)
    print(
        f"{name}: sharpe={r['mean_sharpe']:.3f} d={r['mean_d_sharpe']:+.3f} "
        f"mdd={r['median_mdd']:.3f} wf={wf:.3f} SCORE={sc:.3f}"
    )
