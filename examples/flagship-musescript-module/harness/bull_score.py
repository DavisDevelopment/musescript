#!/usr/bin/env python3
"""Score the bull-twin genome on bull walk-forwards (and contrast vs champion)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"

LIQUID10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
AVAILABLE = LIQUID10 + ["JPM", "XOM", "TSLA", "BAC", "WMT"]
BULL_WINDOWS = ["wf_2019q1", "wf_2024q4"]


def score(src: str, win: str, sym: str) -> tuple[bool, float, int, float, float]:
    tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
    m = run_gene(src, tape, execution="next-open", cost_bps=10)
    bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
    d = m.sharpe - bh.sharpe
    ok = bool(m.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25)
    return ok, d, m.trades, m.sharpe, bh.sharpe


def run_batch(label: str, src: str, symbols: list[str]) -> None:
    print(f"==== {label} ====")
    total_ok = total = 0
    for win in BULL_WINDOWS:
        n = 0
        bits = []
        for sym in symbols:
            ok, d, tr, sh, bh = score(src, win, sym)
            n += int(ok)
            total += 1
            total_ok += int(ok)
            mark = "P" if ok else "f"
            bits.append(f"{sym}:{mark}(d={d:+.2f},tr={tr})")
        print(f"  {win}: {n}/{len(symbols)}")
        print("   ", " ".join(bits))
    print(f"  BULL TWIN TOTAL: {total_ok}/{total} ({100.0 * total_ok / total:.1f}%)\n")


def main() -> int:
    bull_rel = sys.argv[1] if len(sys.argv) > 1 else "strategies/flagship_bull.ms"
    champ_rel = sys.argv[2] if len(sys.argv) > 2 else "strategies/flagship_v6l.ms"
    bull = stitch_source(ROOT / "examples/flagship-musescript-module" / bull_rel)
    champ = stitch_source(ROOT / "examples/flagship-musescript-module" / champ_rel)

    run_batch(f"BULL twin ({Path(bull_rel).name}) liquid10", bull, LIQUID10)
    run_batch(f"CHAMP ({Path(champ_rel).name}) liquid10 contrast", champ, LIQUID10)
    run_batch(f"BULL twin available", bull, AVAILABLE)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
