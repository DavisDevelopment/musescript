#!/usr/bin/env python3
"""Debug class-form seed after StrategyDecl fix."""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

VARIANTS = {
    "class_seed_only": """
class S extends FlagshipRisk {
  r5 = rsi(close, 5)
  function onBar() {
    when bar_index == 1: long()
    when bar_index >= 55 && r5 < 45: flat()
  }
  function hardStopped() { return false }
  function timedOut() { return false }
  function profitLocked() { return false }
}
""",
    "class_seed_super_off": """
class S extends FlagshipRisk {
  r5 = rsi(close, 5)
  function onBar() {
    when bar_index == 1: long()
    when bar_index >= 55 && r5 < 45: flat()
  }
  function onPosition() {
    // intentionally empty — kill inherited risk exits
  }
}
""",
    "class_seed_no_extend": """
class S extends muse.Strat {
  r5 = rsi(close, 5)
  function onBar() {
    when bar_index == 1: long()
    when bar_index >= 55 && r5 < 45: flat()
  }
}
""",
    "v2_rescore": (
        ROOT / "examples/flagship-musescript-module/strategies/flagship_v2.ms"
    ).read_text(encoding="utf-8"),
}


def main() -> int:
    for name, src in VARIANTS.items():
        tmp = ROOT / "examples/flagship-musescript-module/strategies/probes" / f"_dbg2_{name}.ms"
        tmp.write_text(src.strip() + "\n", encoding="utf-8")
        stitched = stitch_source(tmp)
        print(f"\n===== {name} =====")
        for win in ["eval_3m", "wf_2022q1"]:
            for sym in ["IWM", "SPY", "AAPL", "MSFT", "QQQ"]:
                tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
                if not tape.exists():
                    continue
                m = run_gene(stitched, tape, execution="next-open", cost_bps=10)
                bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
                if not m.ok:
                    print(f"  {win} {sym}: ERR {m.error[:80]}")
                    continue
                d = m.sharpe - bh.sharpe
                ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
                print(
                    f"  {win} {sym}: sh={m.sharpe:+.3f} d={d:+.3f} tr={m.trades} "
                    f"ret={m.total_return:+.2%} {'PASS' if ok else 'weak'}"
                )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
