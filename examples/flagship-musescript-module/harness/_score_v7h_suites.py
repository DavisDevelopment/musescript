#!/usr/bin/env python3
"""Score v7h dual/bulls/corpus with viz publish."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(MOD / "harness"))
from viz_core import publish_job_done, run_bulls, run_corpus, run_dual  # noqa: E402


def main() -> int:
    strat = MOD / "strategies/flagship_v7h.ms"
    if len(sys.argv) > 1:
        strat = MOD / sys.argv[1]
    print("==== scoring", strat.name, "====")
    for name, fn in [("dual", run_dual), ("bulls", run_bulls), ("corpus", run_corpus)]:
        r = fn(strat)
        publish_job_done(source="agent")
        print(
            f"{name}: {r['n_pass']}/{r['n_total']} ({r['pct']}%) "
            f"mean_d={r['mean_d_sharpe']:+.4f}"
        )
        for win, w in r.get("by_window", {}).items():
            print(f"  {win}: {w['n_pass']}/{w['n_total']}")
        fails = [c for c in r["cells"] if not c.get("pass")]
        if fails:
            bits = []
            for c in fails[:24]:
                w = c["window"].replace("wf_", "").replace("eval_3m", "eval")
                bits.append(f"{c['symbol']}@{w}(d={c.get('d_sharpe')})")
            print("  fails:", " ".join(bits))
        soft = [c for c in r["cells"] if c.get("soft_wall")]
        if soft:
            bits = []
            for c in soft:
                mark = "P" if c.get("pass") else "f"
                bits.append(f"{c['symbol']}@{c['window']}:{mark}(d={c.get('d_sharpe')})")
            print("  soft:", " ".join(bits))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
