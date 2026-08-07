#!/usr/bin/env python3
"""Dual-window liquid10 score probe — publishes to viz_state for the observer.

Uses warm batch-runner (one Node spawn for the whole grid) when ≥2 jobs.
"""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from eval import Metrics, buy_hold_source, run_gene_batch, stitch_source  # noqa: E402
from viz_core import (  # noqa: E402
    LIQUID10,
    publish_cell,
    publish_job_done,
    publish_job_start,
    publish_run,
)

SYMS = LIQUID10
WINS = ["eval_3m", "wf_2022q1"]


def main() -> int:
    rel = sys.argv[1] if len(sys.argv) > 1 else "strategies/flagship_v7g.ms"
    path = ROOT / "examples/flagship-musescript-module" / rel
    if not path.exists():
        path = Path(rel)
    st = stitch_source(path)
    bh = buy_hold_source()
    print("====", path.name, "====")
    total = len(WINS) * len(SYMS)
    publish_job_start("dual", path.name, total=total, agent="score_probe", source="cli")

    plan = [(w, s) for w in WINS for s in SYMS]
    jobs: list[dict] = []
    for win, sym in plan:
        tape = ROOT / f"examples/flagship-musescript-module/tapes/{win}/{sym}.csv"
        jobs.append(
            {
                "id": f"{win}|{sym}|strat",
                "source": st,
                "tape": str(tape),
                "execution": "next-open",
                "costBps": 10,
            }
        )
        jobs.append(
            {
                "id": f"{win}|{sym}|bh",
                "source": bh,
                "tape": str(tape),
                "execution": "next-open",
                "costBps": 10,
            }
        )

    cells: list[dict] = []
    n_pass = 0
    d_sum = 0.0
    d_n = 0
    done = 0
    by_id: dict[str, Metrics] = {}
    flushed: set[str] = set()

    def maybe_publish(win: str, sym: str) -> None:
        nonlocal done, n_pass, d_sum, d_n
        key = f"{win}|{sym}"
        if key in flushed:
            return
        mk = f"{win}|{sym}|strat"
        bk = f"{win}|{sym}|bh"
        if mk not in by_id or bk not in by_id:
            return
        flushed.add(key)
        m, bh_m = by_id[mk], by_id[bk]
        done += 1
        remaining = [
            f"{s}@{w.replace('wf_', '').replace('eval_3m', 'eval')}" for w, s in plan[done:]
        ]
        if not m.ok:
            cell = {
                "symbol": sym,
                "window": win,
                "ok": False,
                "pass": False,
                "soft_wall": False,
                "error": m.error,
                "d_sharpe": None,
                "sharpe": None,
                "bh_sharpe": bh_m.sharpe if bh_m.ok else None,
                "trades": None,
                "ret": None,
                "mdd": None,
            }
            mark = "ERR"
            det_d = None
        else:
            d = m.sharpe - bh_m.sharpe
            ok = m.trades >= 1 and m.sharpe > 0 and d > 0 and m.max_drawdown <= 0.25
            if ok:
                n_pass += 1
                d_sum += d
                d_n += 1
            cell = {
                "symbol": sym,
                "window": win,
                "ok": True,
                "pass": ok,
                "soft_wall": False,
                "error": None,
                "d_sharpe": round(d, 4),
                "sharpe": round(m.sharpe, 4),
                "bh_sharpe": round(bh_m.sharpe, 4),
                "trades": m.trades,
                "ret": round(m.total_return, 4),
                "mdd": round(m.max_drawdown, 4),
            }
            mark = "P" if ok else "f"
            det_d = d
        cells.append(cell)
        mean = round((d_sum / d_n) if d_n else 0.0, 4)
        publish_cell(
            "dual",
            path.name,
            cell,
            done=done,
            total=total,
            n_pass=n_pass,
            mean_d_sharpe=mean,
            remaining=remaining[:12],
            remaining_n=len(remaining),
            source="cli",
        )
        # stash detail for window summary printing after batch
        cell["_det"] = (
            f"{sym}:ERR"
            if mark == "ERR"
            else f"{sym}:{mark}(d={det_d:+.2f},tr={m.trades})"
        )

    try:

        def on_result(jid: str, m: Metrics, _raw: dict) -> None:
            by_id[jid] = m
            parts = jid.split("|")
            if len(parts) == 3:
                maybe_publish(parts[0], parts[1])

        run_gene_batch(jobs, on_result=on_result)

        # Window summaries (preserve old CLI shape)
        for win in WINS:
            wcells = [c for c in cells if c["window"] == win]
            wpass = sum(1 for c in wcells if c.get("pass"))
            det = [c.get("_det", c["symbol"]) for c in wcells]
            fails = [d for d, c in zip(det, wcells) if not c.get("pass")]
            print(f"  {win}: {wpass}/{len(SYMS)}")
            print("  ", " ".join(det))
            if fails:
                print("  fails", fails)

        mean = round((d_sum / d_n) if d_n else 0.0, 4)
        # Strip internal annotation before publish_run
        clean = [{k: v for k, v in c.items() if k != "_det"} for c in cells]
        result = {
            "suite": "dual",
            "strategy": path.name,
            "n_pass": n_pass,
            "n_total": total,
            "pct": round(100.0 * n_pass / total, 1),
            "mean_d_sharpe": mean,
            "cells": clean,
        }
        publish_run("dual", path.name, result, source="cli", agent="score_probe")
        publish_job_done(source="cli")
    except Exception as e:
        publish_job_done(error=str(e), source="cli")
        raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
