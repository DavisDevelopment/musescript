#!/usr/bin/env python3
"""Near-full corpus coverage probe across available symbols × key windows.

Uses warm batch-runner — one Node spawn for the whole corpus (strategy + BH).
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import Metrics, buy_hold_source, run_gene_batch, stitch_source  # noqa: E402

AVAILABLE = [
    "SPY",
    "QQQ",
    "IWM",
    "AAPL",
    "MSFT",
    "GOOGL",
    "AMZN",
    "META",
    "NVDA",
    "JPM",
    "XOM",
    "TSLA",
    "AMD",
    "BAC",
    "WMT",
]
WINDOWS = ["eval_3m", "wf_2022q1", "wf_2019q1", "wf_2024q4"]
LIQUID10 = ["SPY", "QQQ", "IWM", "AAPL", "MSFT", "NVDA", "AMD", "AMZN", "GOOGL", "META"]


def _cell_ok(m: Metrics, bh: Metrics) -> tuple[bool, str, str]:
    if not m.ok:
        return False, "ERR", ""
    d = m.sharpe - bh.sharpe
    ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
    mark = "P" if ok else "f"
    return ok, mark, f"d={d:+.2f},tr={m.trades}"


def main() -> int:
    rel = sys.argv[1] if len(sys.argv) > 1 else "strategies/flagship_v7g.ms"
    path = ROOT / "examples/flagship-musescript-module" / rel
    st = stitch_source(path)
    bh_src = buy_hold_source()
    print("====", path.name, "corpus ====")

    # One warm batch for liquid10 dual + full available×4 (de-dupe overlapping cells).
    jobs: list[dict] = []
    seen: set[str] = set()
    for win in WINDOWS:
        for sym in AVAILABLE:
            jid = f"{win}|{sym}"
            if jid in seen:
                continue
            seen.add(jid)
            tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
            if not tape.exists():
                continue
            jobs.append({"id": f"{jid}|strat", "source": st, "tape": str(tape), "execution": "next-open", "costBps": 10})
            jobs.append({"id": f"{jid}|bh", "source": bh_src, "tape": str(tape), "execution": "next-open", "costBps": 10})

    out = run_gene_batch(jobs)

    def score_cell(win: str, sym: str) -> tuple[bool, str]:
        tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
        if not tape.exists():
            return False, "MISS"
        m = out.get(f"{win}|{sym}|strat", Metrics(ok=False, error="missing"))
        bh = out.get(f"{win}|{sym}|bh", Metrics(ok=False, error="missing"))
        ok, mark, det = _cell_ok(m, bh)
        if mark == "ERR":
            return False, f"{sym}:ERR"
        return ok, f"{sym}:{mark}({det})"

    for win in ["eval_3m", "wf_2022q1"]:
        npass = n = 0
        det = []
        fails = []
        for sym in LIQUID10:
            ok, s = score_cell(win, sym)
            n += 1
            npass += int(ok)
            det.append(s)
            if not ok:
                fails.append(s)
        print(f"  liquid10/{win}: {npass}/{n}")
        print("  ", " ".join(det))
        if fails:
            print("  fails", fails)

    total_pass = total = 0
    for win in WINDOWS:
        npass = n = 0
        weak = []
        for sym in AVAILABLE:
            ok, s = score_cell(win, sym)
            n += 1
            npass += int(ok)
            if not ok:
                weak.append(s)
        total_pass += npass
        total += n
        print(f"  available/{win}: {npass}/{n}")
        if weak:
            print("   weak", " ".join(weak))
    print(f"  CORPUS: {total_pass}/{total} ({100.0 * total_pass / total:.1f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
