"""Score leftover probes vs v7h baseline on focus cells + dual/bull soft walls."""
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(MOD / "harness"))
from eval import Metrics, buy_hold_source, run_gene_batch, stitch_source  # noqa: E402

FOCUS = [
    ("eval_3m", "JPM"),
    ("eval_3m", "XOM"),
    ("eval_3m", "TSLA"),
    ("eval_3m", "BAC"),
    ("eval_3m", "WMT"),
    ("wf_2022q1", "JPM"),
    ("wf_2022q1", "XOM"),
    ("wf_2022q1", "TSLA"),
    ("wf_2022q1", "BAC"),
    ("wf_2022q1", "WMT"),
    ("wf_2019q1", "JPM"),
    ("wf_2019q1", "XOM"),
    ("wf_2019q1", "TSLA"),
    ("wf_2019q1", "BAC"),
    ("wf_2019q1", "WMT"),
    ("wf_2024q4", "JPM"),
    ("wf_2024q4", "XOM"),
    ("wf_2024q4", "TSLA"),
    ("wf_2024q4", "BAC"),
    ("wf_2024q4", "WMT"),
]

# Soft-wall / tip-lock holders that must not regress
HOLD = [
    ("wf_2019q1", "QQQ"),
    ("wf_2019q1", "NVDA"),
    ("wf_2019q1", "AMD"),
    ("wf_2019q1", "GOOGL"),
    ("wf_2019q1", "META"),
    ("wf_2019q1", "AMZN"),
    ("wf_2019q1", "IWM"),
    ("wf_2024q4", "QQQ"),
    ("wf_2024q4", "NVDA"),
    ("wf_2024q4", "AMD"),
    ("wf_2024q4", "GOOGL"),
    ("eval_3m", "NVDA"),
    ("eval_3m", "AMD"),
    ("eval_3m", "GOOGL"),
    ("eval_3m", "QQQ"),
    ("wf_2022q1", "NVDA"),
    ("wf_2022q1", "AMD"),
    ("wf_2022q1", "GOOGL"),
    ("wf_2022q1", "QQQ"),
    ("wf_2022q1", "IWM"),
    ("wf_2022q1", "META"),
    ("wf_2022q1", "AMZN"),
]


def ok(m: Metrics, bh: Metrics) -> bool:
    return bool(m.ok and m.trades >= 1 and m.sharpe > 0 and (m.sharpe - bh.sharpe) > 0 and m.max_drawdown <= 0.25)


def score(rel: str) -> dict:
    path = MOD / rel if not rel.startswith("strategies") else MOD / rel
    if not Path(rel).is_absolute():
        path = MOD / rel
    else:
        path = Path(rel)
    st = stitch_source(path)
    bh_src = buy_hold_source()
    cells = list(dict.fromkeys(FOCUS + HOLD))
    jobs = []
    for win, sym in cells:
        tape = MOD / f"tapes/{win}/{sym}.csv"
        jid = f"{win}|{sym}"
        jobs.append({"id": f"{jid}|s", "source": st, "tape": str(tape), "execution": "next-open", "costBps": 10})
        jobs.append({"id": f"{jid}|b", "source": bh_src, "tape": str(tape), "execution": "next-open", "costBps": 10})
    out = run_gene_batch(jobs)
    focus_p = hold_p = 0
    focus_f = []
    hold_f = []
    unlocks = []
    for win, sym in FOCUS:
        m = out[f"{win}|{sym}|s"]
        bh = out[f"{win}|{sym}|b"]
        d = m.sharpe - bh.sharpe
        p = ok(m, bh)
        focus_p += int(p)
        tag = f"{sym}@{win.replace('wf_','').replace('eval_3m','eval')}"
        if not p:
            focus_f.append(f"{tag}(sh={m.sharpe:+.2f},d={d:+.2f})")
        else:
            unlocks.append(tag)
    for win, sym in HOLD:
        m = out[f"{win}|{sym}|s"]
        bh = out[f"{win}|{sym}|b"]
        p = ok(m, bh)
        hold_p += int(p)
        if not p:
            d = m.sharpe - bh.sharpe
            hold_f.append(f"{sym}@{win}(sh={m.sharpe:+.2f},d={d:+.2f})")
    return {
        "name": path.name,
        "focus": f"{focus_p}/{len(FOCUS)}",
        "hold": f"{hold_p}/{len(HOLD)}",
        "focus_pass": focus_p,
        "hold_pass": hold_p,
        "unlocks": unlocks,
        "focus_f": focus_f,
        "hold_f": hold_f,
    }


def main() -> int:
    probes = [sys.argv[1]] if len(sys.argv) > 1 else [
        "strategies/flagship_v7h.ms",
        *[f"strategies/probes/{p.name}" for p in sorted((MOD / "strategies/probes").glob("_p_v7h_{jpm,tsla,xom,bac,wmt}*".replace("{jpm,tsla,xom,bac,wmt}", "*")))],
    ]
    # Filter to leftover probe names if scanning
    if len(sys.argv) == 1:
        keys = ("_p_v7h_jpm_", "_p_v7h_tsla_", "_p_v7h_xom_", "_p_v7h_bac_", "_p_v7h_wmt_")
        probes = ["strategies/flagship_v7h.ms"] + [
            f"strategies/probes/{p.name}"
            for p in sorted((MOD / "strategies/probes").iterdir())
            if p.name.startswith(keys)
        ]
    print(f"scoring {len(probes)} strategies")
    rows = []
    for rel in probes:
        try:
            r = score(rel)
        except Exception as e:
            print(f"ERR {rel}: {e}")
            continue
        rows.append(r)
        mark = "OK" if not r["hold_f"] else "REGRESS"
        print(
            f"{r['name']:28} focus {r['focus']} hold {r['hold']} [{mark}] "
            f"pass_focus={r['unlocks'][:8]}"
        )
        if r["hold_f"]:
            print("  HOLD FAIL", " ".join(r["hold_f"][:8]))
        if r["focus_f"] and r["name"] != "flagship_v7h.ms":
            # show delta-ish: only list fails
            pass
    # baseline focus pass count
    base = next((r for r in rows if r["name"] == "flagship_v7h.ms"), None)
    if base:
        print("\n==== lifts vs baseline focus", base["focus"], "====")
        for r in rows:
            if r["name"] == base["name"]:
                continue
            d = r["focus_pass"] - base["focus_pass"]
            if d > 0 and not r["hold_f"]:
                gained = sorted(set(r["unlocks"]) - set(base["unlocks"]))
                lost = sorted(set(base["unlocks"]) - set(r["unlocks"]))
                print(f"  +{d} {r['name']} gained={gained} lost={lost}")
            elif d > 0:
                print(f"  +{d} {r['name']} but HOLD REGRESS {r['hold_f'][:4]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
