#!/usr/bin/env python3
"""Bakeoff harness for v7 OOB candidates vs champion.

Scores each strategies/v7_*.ms (plus optional args) on:
  - liquid10 dual (eval_3m, wf_2022q1)
  - liquid10 bulls (wf_2019q1, wf_2024q4)
  - available×4 corpus pass rate (light)

Usage:
  python examples/flagship-musescript-module/harness/v7_bakeoff.py
  python examples/flagship-musescript-module/harness/v7_bakeoff.py strategies/flagship_v6l.ms strategies/v7_meta_kelly.ms
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
LIQUID10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
AVAILABLE = LIQUID10 + ["JPM", "XOM", "TSLA", "BAC", "WMT"]
DUAL = ["eval_3m", "wf_2022q1"]
BULLS = ["wf_2019q1", "wf_2024q4"]
CORPUS_WINS = DUAL + BULLS


def ok_cell(src: str, win: str, sym: str) -> tuple[bool, float]:
    tape = MOD / "tapes" / win / f"{sym}.csv"
    if not tape.exists():
        return False, 0.0
    m = run_gene(src, tape, execution="next-open", cost_bps=10)
    bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
    if not m.ok:
        return False, 0.0
    d = m.sharpe - bh.sharpe
    ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
    return ok, d


def score_batch(src: str, windows: list[str], symbols: list[str]) -> tuple[int, int, float]:
    n_ok = n = 0
    d_sum = 0.0
    for win in windows:
        for sym in symbols:
            ok, d = ok_cell(src, win, sym)
            n += 1
            n_ok += int(ok)
            if ok:
                d_sum += d
    mean_d = d_sum / n_ok if n_ok else 0.0
    return n_ok, n, mean_d


def discover_candidates(extra: list[str]) -> list[Path]:
    found = sorted((MOD / "strategies").glob("v7_*.ms"))
    out: list[Path] = []
    # Always include champion baseline
    champ = MOD / "strategies" / "flagship_v6l.ms"
    if champ.exists():
        out.append(champ)
    for p in found:
        if p not in out:
            out.append(p)
    for rel in extra:
        p = MOD / rel if not Path(rel).is_absolute() else Path(rel)
        if not p.exists():
            p = ROOT / rel
        if p.exists() and p not in out:
            out.append(p)
    return out


def main() -> int:
    extras = sys.argv[1:]
    cands = discover_candidates(extras)
    if not cands:
        print("no candidates — add strategies/v7_*.ms")
        return 1

    print(f"{'genome':28} {'dual':8} {'bulls':8} {'corpus':10} {'dBH_dual':8}")
    print("-" * 72)
    for path in cands:
        try:
            st = stitch_source(path)
        except Exception as e:
            print(f"{path.name:28} ERR stitch: {e}")
            continue
        d_ok, d_n, d_mean = score_batch(st, DUAL, LIQUID10)
        b_ok, b_n, _ = score_batch(st, BULLS, LIQUID10)
        c_ok, c_n, _ = score_batch(st, CORPUS_WINS, AVAILABLE)
        print(
            f"{path.name:28} {d_ok:2}/{d_n:<5} {b_ok:2}/{b_n:<5} "
            f"{c_ok:2}/{c_n:<7} {d_mean:+7.2f}"
        )
    print("\nSee results/v7_oob_bakeoff.md for candidate DNA.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
