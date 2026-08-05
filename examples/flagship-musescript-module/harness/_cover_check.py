#!/usr/bin/env python3
"""Fast promote checkpoint: dual + bulls + key freq cells."""
from __future__ import annotations
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source, frequency_match, load_json, CONFIGS  # noqa: E402

BH = "strategy BuyHold {\n  onBar {\n    when bar_index == 1: long()\n  }\n}\n"
L10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
freqs = load_json(CONFIGS / "frequencies.json")

gene = sys.argv[1]
st = stitch_source(MOD / gene)


def score(win, sym):
    m = run_gene(st, MOD / f"tapes/{win}/{sym}.csv", execution="next-open", cost_bps=10)
    bh = run_gene(BH, MOD / f"tapes/{win}/{sym}.csv", execution="next-open", cost_bps=10)
    d = m.sharpe - bh.sharpe
    ok = bool(m.ok and m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25)
    return ok, d, m.trades, frequency_match(m, freqs["swing"]), frequency_match(m, freqs["position"])


def batch(wins):
    n = 0
    ds = 0.0
    fails = []
    for w in wins:
        for s in L10:
            ok, d, tr, sw, pos = score(w, s)
            n += int(ok)
            if ok:
                ds += d
            else:
                fails.append(f"{s}@{w[3:]}(d={d:+.2f},tr={tr})")
    return n, ds / max(n, 1), fails


d_ok, d_mean, d_f = batch(["eval_3m", "wf_2022q1"])
b_ok, _, b_f = batch(["wf_2019q1", "wf_2024q4"])
print(f"{Path(gene).name}: dual={d_ok}/20 dBH={d_mean:+.2f} bulls={b_ok}/20")
if d_f:
    print("  dual fail:", " ".join(d_f))
if b_f:
    print("  bull fail:", " ".join(b_f[:12]), ("..." if len(b_f) > 12 else ""))
# Critical freq cells
print("  swing+pos key:")
for w, s in [("wf_2022q1", "META"), ("eval_3m", "IWM"), ("eval_3m", "AAPL"), ("eval_3m", "NVDA"), ("eval_3m", "META"),
             ("wf_2024q4", "NVDA"), ("wf_2024q4", "MSFT"), ("wf_2024q4", "SPY"), ("wf_2024q4", "QQQ")]:
    ok, d, tr, sw, pos = score(w, s)
    both = sw and pos
    print(f"    {s:5} {w:10} {'P' if ok else 'f'} d={d:+.2f} tr={tr} sw={sw} pos={pos} both={both}")
