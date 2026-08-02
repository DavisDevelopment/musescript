#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]


def main() -> int:
    rel = sys.argv[1] if len(sys.argv) > 1 else "strategies/probes/p_v3_abandon_hot.ms"
    path = ROOT / "examples/flagship-musescript-module" / rel
    st = stitch_source(path)
    print("====", path.name, "====")
    for win in ["eval_3m", "wf_2022q1"]:
        npass = n = 0
        fails = []
        det = []
        for sym in SYMS:
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            m = run_gene(st, tape, execution="next-open", cost_bps=10)
            bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
            n += 1
            if not m.ok:
                fails.append(sym + ":ERR")
                det.append(f"{sym}:ERR")
                continue
            d = m.sharpe - bh.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            if ok:
                npass += 1
            else:
                fails.append(f"{sym}:d={d:+.2f}/tr={m.trades}/ret={m.total_return:+.1%}")
            mark = "P" if ok else "f"
            det.append(f"{sym}:{mark}(d={d:+.2f},tr={m.trades})")
        print(f"  {win}: {npass}/{n}")
        print("  ", " ".join(det))
        if fails:
            print("  fails", fails)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
