#!/usr/bin/env python3
"""Debug whether seed-hold survives FlagshipRisk onPosition."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

VARIANTS = {
    "micro_exact": """
strategy S {
  onBar {
    when bar_index == 1: long()
    when bar_index >= 55 && rsi(close, 5) < 45: flat()
  }
}
""",
    "seed_no_risk_class": """
strategy S {
  seedHold = position() > 0 && bars_in_trade >= bar_index - 1
  onBar {
    when bar_index == 1: long()
    when seedHold && bar_index >= 55 && rsi(close, 5) < 45: flat()
    when (!seedHold) && close > ema(close, 8) && high >= highest(high, 21): long()
    when (!seedHold) && (low <= lowest(low, 13) || rsi(close, 13) > 80): flat()
  }
}
""",
    "seed_with_risk_override": """
class S extends FlagshipRisk {
  r5 = rsi(close, 5)
  seedHold = position() > 0 && bars_in_trade >= bar_index - 1

  function onBar() {
    when bar_index == 1: long()
    when seedHold && bar_index >= 55 && r5 < 45: flat()
    when (!seedHold) && softCrownExit(13): flat()
  }

  function hardStopped() { return (!seedHold) && super.hardStopped() }
  function timedOut() { return false }
  function profitLocked() { return false }
}
""",
    "seed_override_onposition": """
class S extends FlagshipRisk {
  r5 = rsi(close, 5)
  seedHold = position() > 0 && bars_in_trade >= bar_index - 1

  function onBar() {
    when bar_index == 1: long()
    when seedHold && bar_index >= 55 && r5 < 45: flat()
  }

  function onPosition() {
    when (!seedHold) && (hardStopped() || timedOut() || profitLocked()): flat()
  }

  function hardStopped() { return unrealized_pnl < -0.05 * equity }
  function timedOut() { return bars_in_trade >= 13 }
  function profitLocked() { return false }
}
""",
}


def main() -> int:
    for name, src in VARIANTS.items():
        tmp = ROOT / "examples/flagship-musescript-module/strategies/probes" / f"_dbg_{name}.ms"
        tmp.write_text(src.strip() + "\n", encoding="utf-8")
        stitched = stitch_source(tmp)
        print(f"\n===== {name} =====")
        for sym in ["IWM", "SPY", "AAPL", "MSFT"]:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/eval_3m/{sym}.csv"
            m = run_gene(stitched, tape, execution="next-open", cost_bps=10)
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            if not m.ok:
                print(f"  {sym}: ERR {m.error[:100]}")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            print(
                f"  {sym}: sh={m.sharpe:+.3f} d={d:+.3f} tr={m.trades} ret={m.total_return:+.2%} "
                f"{'PASS' if ok else 'weak'}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
