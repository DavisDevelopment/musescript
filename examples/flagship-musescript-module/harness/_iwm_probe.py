#!/usr/bin/env python3
"""Quick IWM cell probe across dual + bull windows."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"


def cell(src: str, win: str, sym: str):
    tape = MOD / "tapes" / win / f"{sym}.csv"
    m = run_gene(src, tape, execution="next-open", cost_bps=10)
    bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
    d = m.sharpe - bh.sharpe if m.ok else float("nan")
    ok = m.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
    return ok, d, m.trades, m.total_return, m.max_drawdown, m.sharpe, bh.sharpe


def resolve(name: str) -> Path:
    for p in (MOD / "strategies" / name, MOD / "strategies" / "probes" / name):
        if p.exists():
            return p
    raise FileNotFoundError(name)


def main() -> int:
    names = sys.argv[1:] or ["v7_meta_kelly.ms", "flagship_v6l.ms"]
    for name in names:
        st = stitch_source(resolve(name))
        print("====", name, "====")
        for win in ["eval_3m", "wf_2022q1", "wf_2019q1", "wf_2024q4"]:
            ok, d, tr, ret, dd, sh, bh = cell(st, win, "IWM")
            mark = "P" if ok else "f"
            print(
                f"  {win}: {mark} d={d:+.2f} tr={tr} ret={ret:+.1%} "
                f"sh={sh:+.2f} bh={bh:+.2f} dd={dd:.1%}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
