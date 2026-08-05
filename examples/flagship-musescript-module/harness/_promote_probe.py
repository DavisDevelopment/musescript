#!/usr/bin/env python3
"""Quick freq + bull cell probe for promote path."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source, frequency_match, load_json, CONFIGS  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
LIQUID10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
freqs = load_json(CONFIGS / "frequencies.json")

gene = sys.argv[1] if len(sys.argv) > 1 else "strategies/v7_meta_kelly.ms"
st = stitch_source(MOD / gene)
print(f"==== {gene} ====")


def cell(win: str, sym: str):
    tape = MOD / "tapes" / win / f"{sym}.csv"
    m = run_gene(st, tape, execution="next-open", cost_bps=10)
    bh = run_gene(BH, tape, execution="next-open", cost_bps=10)
    d = m.sharpe - bh.sharpe
    ok = bool(m.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25)
    pos = frequency_match(m, freqs["position"])
    sw = frequency_match(m, freqs["swing"])
    return ok, d, m.trades, m.trades_per_bar, pos, sw, m.sharpe, m.max_drawdown


print(f"\n{'sym':6} {'win':10} {'ok':2} {'d':>6} {'tr':>3} {'tpb':>5} {'pos':>3} {'sw':>3} note")
for win in ["eval_3m", "wf_2022q1"]:
    for sym in LIQUID10:
        ok, d, tr, tpb, pos, sw, sh, mdd = cell(win, sym)
        if pos and sw:
            note = "BOTH"
        elif pos and not sw:
            note = "need+tr"
        elif sw and not pos:
            note = "tooActive"
        else:
            note = "neither"
        mark = "P" if ok else "f"
        print(f"{sym:6} {win:10} {mark:2} {d:+6.2f} {tr:3} {tpb:5.3f} {str(pos)[0]:>3} {str(sw)[0]:>3} {note}")

print("\n==== BULLS ====")
for win in ["wf_2019q1", "wf_2024q4"]:
    n = 0
    bits = []
    for sym in LIQUID10:
        ok, d, tr, tpb, pos, sw, sh, mdd = cell(win, sym)
        n += int(ok)
        mark = "P" if ok else "f"
        bits.append(f"{sym}:{mark}(d={d:+.2f},tr={tr})")
    print(f"{win}: {n}/10")
    print(" ", " ".join(bits))
