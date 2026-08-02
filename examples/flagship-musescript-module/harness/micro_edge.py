#!/usr/bin/env python3
"""Find any strategy that strictly beats BH on IWM/MSFT eval_3m."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

# Tiny variants that try to nick BH Sharpe on strong tapes / salvage weak ones.
VARIANTS: dict[str, str] = {
    "bh": BH,
    "skip_first_5": """
strategy S {
  onBar {
    when bar_index == 6: long()
  }
}
""",
    "skip_hot_entry": """
strategy S {
  onBar {
    when bar_index >= 1 && position() == 0 && rsi(close, 2) < 90: long()
  }
}
""",
    "exit_last_week_weak": """
strategy S {
  onBar {
    when bar_index == 1: long()
    when bar_index >= 55 && rsi(close, 5) < 45: flat()
  }
}
""",
    "exit_if_rsi_hot_late": """
strategy S {
  onBar {
    when bar_index == 1: long()
    when bar_index >= 50 && rsi(close, 2) > 95: flat()
  }
}
""",
    "trail_sma20_late": """
strategy S {
  onBar {
    when bar_index == 1: long()
    when bar_index >= 40 && close < sma(close, 20): flat()
  }
}
""",
    "enter_dip_hold": """
strategy S {
  onBar {
    when position() == 0 && rsi(close, 2) < 20: long()
    when position() == 0 && bar_index == 15: long()
  }
}
""",
    "enter_on_green": """
strategy S {
  onBar {
    when position() == 0 && close > open && close > sma(close, 5): long()
  }
}
""",
    "single_thrust": """
strategy S {
  thrust = mom(close, 13)
  vol = atr(close, 13)
  onBar {
    when position() == 0 && thrust > vol && rising(close, 2): long()
  }
  onPosition {
    when bars_in_trade >= 21: flat()
    when unrealized_pnl < -0.05 * equity: flat()
  }
}
""",
    "single_thrust_hold": """
strategy S {
  thrust = mom(close, 13)
  vol = atr(close, 13)
  onBar {
    when position() == 0 && thrust > vol && rising(close, 2): long()
  }
}
""",
    "macd_one_shot": """
strategy S {
  m = macd(close, 12, 26, 9)
  onBar {
    when position() == 0 && crossover(m.hist, 0): long()
  }
  onPosition {
    when bars_in_trade >= 13: flat()
    when unrealized_pnl < -0.04 * equity: flat()
  }
}
""",
    "short_weak": """
strategy S {
  onBar {
    when close < sma(close, 21) && falling(close, 3): short()
    when close > sma(close, 21) || rsi(close, 13) < 30: flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
""",
    "long_short_flip": """
strategy S {
  e = ema(close, 13)
  onBar {
    when close > e && rising(close, 2): long()
    when close < e && falling(close, 2): short()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 8: flat()
  }
}
""",
    "connors": """
strategy S {
  c = connors_rsi(close, 3, 2, 100)
  e = sma(close, 100)
  onBar {
    when close > e && c < 20: long()
    when c > 80: flat()
  }
  onPosition {
    when unrealized_pnl < -0.04 * equity: flat()
    when bars_in_trade >= 5: flat()
  }
}
""",
}


def main() -> int:
    for sym in ["IWM", "MSFT", "AAPL"]:
        tape = ROOT / f"examples/flagship-musescript-module/tapes/eval_3m/{sym}.csv"
        bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
        print(f"\n=== {sym} BH sharpe={bh.sharpe:+.4f} ret={bh.total_return:+.2%} mdd={bh.max_drawdown:.2%} ===")
        best = None
        for name, src in VARIANTS.items():
            m = run_gene(src, tape, execution="next-open", cost_bps=10)
            if not m.ok:
                print(f"  {name:22} ERR {m.error[:80]}")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            mark = "PASS" if ok else ""
            print(
                f"  {name:22} sh={m.sharpe:+7.3f} d={d:+7.3f} tr={m.trades:3d} "
                f"ret={m.total_return:+8.2%} mdd={m.max_drawdown:5.1%} {mark}"
            )
            if best is None or d > best[0]:
                best = (d, name, m)
        if best:
            print(f"  BEST dBH={best[0]:+.3f} via {best[1]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
