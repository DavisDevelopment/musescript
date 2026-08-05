#!/usr/bin/env python3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import run_gene, stitch_source, frequency_match, load_json, CONFIGS  # noqa: E402

freqs = load_json(CONFIGS / "frequencies.json")
st = stitch_source(ROOT / "examples/flagship-musescript-module/strategies/flagship_v6l.ms")
SYMS = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]
print(f"{'sym':8} {'win':10} {'tr':>3} {'tpb':>6} {'pos':>4} {'swing':>5} note")
for win in ["eval_3m", "wf_2022q1"]:
    for sym in SYMS:
        m = run_gene(st, ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv", execution="next-open", cost_bps=10)
        pos = frequency_match(m, freqs["position"])
        sw = frequency_match(m, freqs["swing"])
        if pos and sw:
            note = "BOTH"
        elif pos and not sw:
            note = "need+tr"
        elif sw and not pos:
            note = "tooActive"
        else:
            note = "neither"
        print(f"{sym:8} {win:10} {m.trades:3} {m.trades_per_bar:6.3f} {str(pos):>4} {str(sw):>5} {note}")
