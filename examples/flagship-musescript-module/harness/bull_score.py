#!/usr/bin/env python3
"""Score the bull-twin genome on bull walk-forwards (and contrast vs champion).

Uses warm batch-runner — one Node spawn covering all (strategy × symbol × window × BH) cells.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import Metrics, buy_hold_source, run_gene_batch, stitch_source  # noqa: E402

LIQUID10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
AVAILABLE = LIQUID10 + ["JPM", "XOM", "TSLA", "BAC", "WMT"]
BULL_WINDOWS = ["wf_2019q1", "wf_2024q4"]


def main() -> int:
    bull_rel = sys.argv[1] if len(sys.argv) > 1 else "strategies/flagship_bull.ms"
    champ_rel = sys.argv[2] if len(sys.argv) > 2 else "strategies/flagship_v7g.ms"
    bull_path = ROOT / "examples/flagship-musescript-module" / bull_rel
    champ_path = ROOT / "examples/flagship-musescript-module" / champ_rel
    bull = stitch_source(bull_path)
    champ = stitch_source(champ_path)
    bh_src = buy_hold_source()

    # Labels → (source, symbols)
    suites: list[tuple[str, str, list[str]]] = [
        (f"BULL twin ({Path(bull_rel).name}) liquid10", bull, LIQUID10),
        (f"CHAMP ({Path(champ_rel).name}) liquid10 contrast", champ, LIQUID10),
        (f"BULL twin available", bull, AVAILABLE),
    ]

    jobs: list[dict] = []
    for label, src, symbols in suites:
        for win in BULL_WINDOWS:
            for sym in symbols:
                tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
                jbase = f"{label}\x1f{win}\x1f{sym}"
                jobs.append(
                    {
                        "id": f"{jbase}\x1fstrat",
                        "source": src,
                        "tape": str(tape),
                        "execution": "next-open",
                        "costBps": 10,
                    }
                )
                jobs.append(
                    {
                        "id": f"{jbase}\x1fbh",
                        "source": bh_src,
                        "tape": str(tape),
                        "execution": "next-open",
                        "costBps": 10,
                    }
                )

    out = run_gene_batch(jobs)

    for label, _src, symbols in suites:
        print(f"==== {label} ====")
        total_ok = total = 0
        for win in BULL_WINDOWS:
            n = 0
            bits = []
            for sym in symbols:
                jbase = f"{label}\x1f{win}\x1f{sym}"
                m = out.get(f"{jbase}\x1fstrat", Metrics(ok=False, error="missing"))
                bh = out.get(f"{jbase}\x1fbh", Metrics(ok=False, error="missing"))
                d = m.sharpe - bh.sharpe if m.ok and bh.ok else 0.0
                ok = bool(m.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25)
                n += int(ok)
                total += 1
                total_ok += int(ok)
                mark = "P" if ok else "f"
                tr = m.trades if m.ok else 0
                bits.append(f"{sym}:{mark}(d={d:+.2f},tr={tr})")
            print(f"  {win}: {n}/{len(symbols)}")
            print("   ", " ".join(bits))
        print(f"  BULL TWIN TOTAL: {total_ok}/{total} ({100.0 * total_ok / total:.1f}%)\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
