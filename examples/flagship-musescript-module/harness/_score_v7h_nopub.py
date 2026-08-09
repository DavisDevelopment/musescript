#!/usr/bin/env python3
"""Score v7h suites without viz publish (avoids Windows viz_state races)."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from viz_core import run_bulls, run_corpus, run_dual  # noqa: E402


def main() -> int:
    strat = ROOT / "strategies/flagship_v7h.ms"
    if len(sys.argv) > 1:
        strat = (ROOT / sys.argv[1]).resolve()
    print("==== scoring", strat.name, "(no publish) ====")
    for name, fn in [("dual", run_dual), ("bulls", run_bulls), ("corpus", run_corpus)]:
        r = fn(strat, publish=False)
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
                ww = c["window"].replace("wf_", "").replace("eval_3m", "eval")
                bits.append(f"{c['symbol']}@{ww}(d={c.get('d_sharpe')})")
            print("  fails:", " ".join(bits))
        soft = [c for c in r["cells"] if c.get("soft_wall")]
        if soft:
            bits = []
            for c in soft:
                mark = "P" if c.get("pass") else "f"
                bits.append(f"{c['symbol']}@{c['window']}:{mark}(d={c.get('d_sharpe')})")
            print("  soft:", " ".join(bits))
        # spotlight XOM/BAC
        if name == "corpus":
            for c in r["cells"]:
                if c["symbol"] in ("XOM", "BAC"):
                    ww = c["window"].replace("wf_", "").replace("eval_3m", "eval")
                    mark = "P" if c.get("pass") else "f"
                    print(
                        f"  focus {c['symbol']}@{ww}:{mark} "
                        f"d={c.get('d_sharpe')} tr={c.get('trades')}"
                    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
