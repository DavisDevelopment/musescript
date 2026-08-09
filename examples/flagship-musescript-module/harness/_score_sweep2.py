"""Score XOM tip + BAC red probe sets."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _score_leftovers import score  # noqa: E402

MOD = Path(__file__).resolve().parents[1]


def main() -> int:
    probes = ["strategies/flagship_v7h.ms"]
    probes += [
        f"strategies/probes/{p.name}"
        for p in sorted((MOD / "strategies/probes").glob("_p_v7h_xom_cut15_tip*.ms"))
    ]
    probes += [
        f"strategies/probes/{p.name}"
        for p in sorted((MOD / "strategies/probes").glob("_p_v7h_bac_red*.ms"))
    ]
    probes += ["strategies/probes/_p_v7h_xom_cut15.ms"]
    base = None
    rows = []
    for rel in probes:
        r = score(rel)
        rows.append(r)
        mark = "OK" if not r["hold_f"] else "REGRESS"
        print(f"{r['name']:32} focus {r['focus']} hold {r['hold']} [{mark}]")
        if r["name"] == "flagship_v7h.ms":
            base = r
    print("==== lifts ====")
    for r in rows:
        if r is base:
            continue
        d = r["focus_pass"] - base["focus_pass"]
        gained = sorted(set(r["unlocks"]) - set(base["unlocks"]))
        lost = sorted(set(base["unlocks"]) - set(r["unlocks"]))
        if d != 0 or gained or lost:
            print(
                f"  d={d:+d} {r['name']} gained={gained} lost={lost} hold_f={r['hold_f'][:3]}"
            )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
