#!/usr/bin/env python3
"""Per-symbol entry-family bakeoff against buy-hold under causal costs."""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import RESULTS, stitch_source, run_gene, rel  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

ALTS: dict[str, str] = {
    "macd": """
strategy MacdRise {
  m = macd(close, 8, 21, 5)
  gate = sma(close, 34)
  onBar {
    when rising(m.hist, 3) && close > gate: long()
    when falling(m.hist, 3, 5) || close < gate: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "atr": """
strategy AtrThrust {
  thrust = mom(close, 13)
  vol = atr(close, 13)
  onBar {
    when thrust > vol && rising(close, 2): long()
    when thrust < 0 || roc(close, 13) < -1: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when falling(thrust, 3, 5): flat()
  }
}
""",
    "pb": """
strategy PullbackEma {
  e8 = ema(close, 8)
  e34 = ema(close, 34)
  onBar {
    when close > e34 && crossover(close, e8): long()
    when crossunder(close, e8) || close < e34: flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "sigmoid": """
strategy SigMom {
  m = mom(close, 13)
  vol = atr(close, 13)
  gate = ml_sigmoid(m / (vol + 0.000000001))
  onBar {
    when gate > 0.62 && rising(close, 2): long()
    when gate < 0.42 || falling(close, 3, 5): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
    "ema1345": """
strategy Ema1345 {
  fast = ema(close, 13)
  slow = ema(close, 45)
  gate = sma(close, 34)
  m = macd(close, 8, 21, 5)
  onBar {
    when (fast > slow || rising(m.hist, 3)) && close > gate: long()
    when crossunder(fast, slow) || close < gate || falling(m.hist, 3, 5): flat()
  }
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
  }
}
""",
}


def main() -> int:
    crown = stitch_source(ROOT / "examples/flagship-musescript-module/strategies/flagship_v1.ms")
    families = {"crown": crown, **ALTS}
    syms = ["MSFT", "META", "AAPL", "IWM", "AMD", "AMZN", "TSLA", "GOOGL", "SPY", "QQQ", "NVDA"]
    windows = ["eval_3m", "wf_2022q1"]
    rows = []
    print(f"{'sym':5} {'win':10} {'fam':8} {'sharpe':8} {'dBH':8} {'trades':6} {'ret':9} mark")
    for win in windows:
        for sym in syms:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            if not tape.exists():
                continue
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            for name, src in families.items():
                m = run_gene(src, tape, execution="next-open", cost_bps=10)
                if not m.ok:
                    print(f"{sym:5} {win:10} {name:8} FAIL {m.error[:50]}")
                    continue
                d = (m.sharpe - bh.sharpe) if bh.ok else float("nan")
                ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
                mark = "PASS" if ok else "weak"
                print(
                    f"{sym:5} {win:10} {name:8} {m.sharpe:+8.3f} {d:+8.3f} "
                    f"{m.trades:6d} {m.total_return:+9.2%} {mark}"
                )
                rows.append(
                    {
                        "symbol": sym,
                        "window": win,
                        "family": name,
                        "sharpe": m.sharpe,
                        "d_sharpe": d,
                        "trades": m.trades,
                        "ret": m.total_return,
                        "mdd": m.max_drawdown,
                        "pass": ok,
                    }
                )

    # Best family per (sym, window) by pass then dBH
    print("\n=== BEST PER SYMBOL/WINDOW ===")
    from collections import defaultdict

    best: dict[tuple[str, str], dict] = {}
    for r in rows:
        key = (r["symbol"], r["window"])
        cur = best.get(key)
        if cur is None:
            best[key] = r
            continue
        if (r["pass"], r["d_sharpe"]) > (cur["pass"], cur["d_sharpe"]):
            best[key] = r
    for (sym, win), r in sorted(best.items()):
        print(
            f"{sym:5} {win:10} -> {r['family']:8} "
            f"dBH={r['d_sharpe']:+.3f} sharpe={r['sharpe']:+.3f} "
            f"trades={r['trades']} {'PASS' if r['pass'] else 'weak'}"
        )

    RESULTS.mkdir(parents=True, exist_ok=True)
    out = RESULTS / "family_bakeoff.json"
    out.write_text(json.dumps({"rows": rows, "best": {f"{k[0]}|{k[1]}": v for k, v in best.items()}}, indent=2), encoding="utf-8")
    print(f"\nwrote {rel(out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
