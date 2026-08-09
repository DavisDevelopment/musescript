#!/usr/bin/env python3
"""Score tip-robustness probes: dual → bulls → corpus; fail-fast on dual loss."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from viz_core import run_bulls, run_corpus, run_dual  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
FOCUS = ("BAC", "JPM", "WMT", "XOM")


def briefly(r: dict, suite: str) -> str:
    fails = [c for c in r["cells"] if not c.get("pass")]
    fb = []
    for c in fails[:8]:
        w = c["window"].replace("wf_", "").replace("eval_3m", "eval")
        fb.append(f"{c['symbol']}@{w}")
    focus_bits = []
    for c in r["cells"]:
        if c["symbol"] in FOCUS:
            w = c["window"].replace("wf_", "").replace("eval_3m", "eval")
            mark = "P" if c.get("pass") else "f"
            if suite == "corpus" or c["symbol"] in ("BAC", "JPM", "WMT"):
                focus_bits.append(f"{c['symbol']}@{w}:{mark}(d={c.get('d_sharpe')},tr={c.get('trades')})")
    return (
        f"{r['n_pass']}/{r['n_total']} d={r['mean_d_sharpe']:+.4f}"
        + (f" fails={' '.join(fb)}" if fb else "")
        + (f" | {' '.join(focus_bits[:12])}" if focus_bits and suite != "dual" else "")
    )


def score_one(rel: str, *, full: bool = True) -> dict:
    path = ROOT / rel
    out = {"name": path.name, "ok": True}
    d = run_dual(path, publish=False)
    out["dual"] = briefly(d, "dual")
    out["dual_ok"] = d["n_pass"] == d["n_total"]
    if not out["dual_ok"]:
        out["ok"] = False
        print(f"FAIL dual {path.name}: {out['dual']}")
        return out
    b = run_bulls(path, publish=False)
    out["bulls"] = briefly(b, "bulls")
    out["bulls_ok"] = b["n_pass"] == b["n_total"]
    if not out["bulls_ok"]:
        out["ok"] = False
        print(f"FAIL bulls {path.name}: {out['bulls']}")
        return out
    if full:
        c = run_corpus(path, publish=False)
        out["corpus"] = briefly(c, "corpus")
        out["corpus_ok"] = c["n_pass"] == c["n_total"]
        out["mean_d"] = c["mean_d_sharpe"]
        if not out["corpus_ok"]:
            out["ok"] = False
            print(f"FAIL corpus {path.name}: {out['corpus']}")
            return out
    mark = "PASS" if out["ok"] else "FAIL"
    extra = f" corpus={out.get('corpus', 'skip')}" if full else ""
    print(f"{mark} {path.name}: dual={out['dual']} bulls={out['bulls']}{extra}")
    return out


def main() -> int:
    args = sys.argv[1:]
    if not args:
        args = sorted(str(p.relative_to(ROOT)).replace("\\", "/") for p in (ROOT / "strategies/probes").glob("_p_v7h7_*.ms"))
    for rel in args:
        score_one(rel, full=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
