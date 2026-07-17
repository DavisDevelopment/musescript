import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[5]
LAB = ROOT / "examples/strategy-tournament/harness/tournament_lab.py"
PROBE = Path(__file__).resolve().parent

probes = {
    "base": """strategy Base {
  onBar { when high >= highest(high, 21): long(); when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "macd_exit": """strategy MacdExit {
  onBar { m = macd(close, 8, 21, 5)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "profit8_3": """strategy Profit8 {
  onBar { when high >= highest(high, 21): long(); when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat() }
}""",
    "exit8_low": """strategy Exit8 {
  onBar { when high >= highest(high, 21): long()
    when low <= lowest(low, 8) || low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "ema21_gate": """strategy EmaGate {
  onBar { when close > ema(close, 21) && high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "time8": """strategy Time8 {
  onBar { when high >= highest(high, 21): long(); when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 8: flat(); when unrealized_pnl < -0.05 * equity: flat() }
}""",
    "profit8_exit13": """strategy ProfitExit {
  onBar { when high >= highest(high, 21): long(); when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.04 * equity: flat()
    when bars_in_trade >= 5 && unrealized_pnl < -0.03 * equity: flat() }
}""",
    "staged_exit": """strategy Staged {
  onBar { when high >= highest(high, 21): long()
    when low <= lowest(low, 13): flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8 && low <= lowest(low, 8): flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat() }
}""",
    "macd_profit": """strategy MacdProfit {
  onBar { m = macd(close, 8, 21, 5)
    when high >= highest(high, 21): long()
    when low <= lowest(low, 13) || m.hist < 0: flat() }
  onPosition { when bars_in_trade >= 13: flat(); when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat() }
}""",
}

for name, src in probes.items():
    (PROBE / f"{name}.ms").write_text(src)


def partial_score(r):
    ms = r.get("mean_sharpe") or 0
    ds = r.get("mean_d_sharpe") or 0
    mdd = r.get("median_mdd") or 1
    return 0.40 * ms + 0.25 * ds + 0.20 * (1 - min(mdd, 1))


for name in probes:
    p = PROBE / f"{name}.ms"
    out = subprocess.check_output([sys.executable, str(LAB), "--eval", str(p)], text=True)
    r = json.loads(out)
    print(
        f"{name}: sharpe={r['mean_sharpe']:.3f} d={r['mean_d_sharpe']:+.3f} "
        f"mdd={r['median_mdd']:.3f} partial={partial_score(r):.3f}"
    )
