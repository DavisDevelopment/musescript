#!/usr/bin/env python3
"""Quick multi-cell absolute-metric dump for a strategy."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"


def main() -> int:
    rel = sys.argv[1] if len(sys.argv) > 1 else "strategies/flagship_v7b.ms"
    st = stitch_source(ROOT / "examples/flagship-musescript-module" / rel)
    cells = [tuple(x.split(":")) for x in sys.argv[2:]] if len(sys.argv) > 2 else [
        ("wf_2022q1", "WMT"),
        ("wf_2024q4", "WMT"),
        ("eval_3m", "WMT"),
        ("wf_2019q1", "WMT"),
        ("wf_2024q4", "AMD"),
        ("wf_2019q1", "MSFT"),
        ("wf_2024q4", "AMZN"),
        ("wf_2024q4", "GOOGL"),
        ("wf_2024q4", "AAPL"),
        ("eval_3m", "AMD"),
        ("wf_2022q1", "AMD"),
        ("eval_3m", "MSFT"),
        ("wf_2022q1", "MSFT"),
        ("eval_3m", "AMZN"),
        ("wf_2022q1", "AMZN"),
    ]
    print("====", Path(rel).name, "====")
    for win, sym in cells:
        tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
        m = run_gene(st, tape, execution="next-open", cost_bps=10)
        bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
        d = m.sharpe - bh.sharpe
        ok = bool(m.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25)
        print(
            f"{sym:5} {win:10} {'P' if ok else 'f'} "
            f"sh={m.sharpe:+.3f} bh={bh.sharpe:+.3f} d={d:+.3f} "
            f"tr={m.trades} mdd={m.max_drawdown:.3f} ret={m.total_return:+.3%}"
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
