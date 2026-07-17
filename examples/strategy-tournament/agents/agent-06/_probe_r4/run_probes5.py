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

probes = {
    "flagship": """strategy Flagship {
  onBar { m = macd(close, 13, 34, 8)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0 || rsi(close, 13) > 72: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "flagship_ema13": """strategy FlagshipE13 {
  onBar { m = macd(close, 13, 34, 8); t = ema(close, 13)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0 || rsi(close, 13) > 72 || close < t: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "flagship_layered": """strategy FlagshipLayer {
  onBar { m = macd(close, 13, 34, 8)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0 || rsi(close, 13) > 72: flat() }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < ema(close, 13): flat()
  }
}""",
    "flagship_rsi68": """strategy FlagshipR68 {
  onBar { m = macd(close, 13, 34, 8)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0 || rsi(close, 13) > 68: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "flagship_don13": """strategy FlagshipD13 {
  onBar { m = macd(close, 13, 34, 8)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 8) || m.hist < 0 || rsi(close, 13) > 72: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "flagship_time21": """strategy FlagshipT21 {
  onBar { m = macd(close, 13, 34, 8)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0 || rsi(close, 13) > 72: flat() }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 21: flat()
    when bars_in_trade >= 13 && unrealized_pnl > 0.04 * equity: flat()
  }
}""",
    "flagship_dual_entry": """strategy FlagshipDual {
  onBar { m = macd(close, 13, 34, 8); e8 = ema(close, 8); e34 = ema(close, 34)
    when high >= highest(high, 21): long()
    when e8 > e34 && high >= highest(high, 13): long()
    when low <= lowest(low, 13) || m.hist < 0 || rsi(close, 13) > 72: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
}


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


for name, src in probes.items():
    (PROBE / f"{name}.ms").write_text(src)

rows = []
for name in probes:
    p = PROBE / f"{name}.ms"
    r = json.loads(subprocess.check_output([sys.executable, str(LAB), "--eval", str(p)], text=True))
    wf = wf_sharpe(p)
    rows.append((full_score(r, wf), name, r, wf))

for sc, name, r, wf in sorted(rows, reverse=True):
    print(f"{name}: sharpe={r['mean_sharpe']:.3f} d={r['mean_d_sharpe']:+.3f} mdd={r['median_mdd']:.3f} wf={wf:.3f} SCORE={sc:.3f}")
