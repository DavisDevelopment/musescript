#!/usr/bin/env python3
"""Near-full corpus coverage probe across available symbols × key windows."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

AVAILABLE = [
    "SPY", "QQQ", "IWM", "AAPL", "MSFT", "GOOGL", "AMZN", "META",
    "NVDA", "JPM", "XOM", "TSLA", "AMD", "BAC", "WMT",
]
WINDOWS = ["eval_3m", "wf_2022q1", "wf_2019q1", "wf_2024q4"]
LIQUID10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]


def score_cell(src: str, win: str, sym: str) -> tuple[bool, str]:
    tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
    if not tape.exists():
        return False, "MISS"
    m = run_gene(src, tape, execution="next-open", cost_bps=10)
    bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
    if not m.ok:
        return False, "ERR"
    d = m.sharpe - bh.sharpe
    ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
    mark = "P" if ok else "f"
    return ok, f"{sym}:{mark}(d={d:+.2f},tr={m.trades})"


def main() -> int:
    rel = sys.argv[1] if len(sys.argv) > 1 else "strategies/flagship_v6.ms"
    path = ROOT / "examples/flagship-musescript-module" / rel
    st = stitch_source(path)
    print("====", path.name, "corpus ====")

    # Headline liquid10 dual-window (backward compatible with score_probe)
    for win in ["eval_3m", "wf_2022q1"]:
        npass = n = 0
        det = []
        fails = []
        for sym in LIQUID10:
            ok, s = score_cell(st, win, sym)
            n += 1
            npass += int(ok)
            det.append(s)
            if not ok:
                fails.append(s)
        print(f"  liquid10/{win}: {npass}/{n}")
        print("  ", " ".join(det))
        if fails:
            print("  fails", fails)

    # Full available × 4 windows
    total_pass = total = 0
    by_win: dict[str, list[int]] = {}
    for win in WINDOWS:
        npass = n = 0
        weak = []
        for sym in AVAILABLE:
            ok, s = score_cell(st, win, sym)
            n += 1
            npass += int(ok)
            if not ok:
                weak.append(s)
        by_win[win] = [npass, n]
        total_pass += npass
        total += n
        print(f"  available/{win}: {npass}/{n}")
        if weak:
            print("   weak", " ".join(weak))
    print(f"  CORPUS: {total_pass}/{total} ({100.0 * total_pass / total:.1f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
