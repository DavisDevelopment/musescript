"""Score mild-band leftover probes vs v7h."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _score_leftovers import score  # noqa: E402

MOD = Path(__file__).resolve().parents[1]


def main() -> int:
    probes = ["strategies/flagship_v7h.ms"]
    keys = (
        "_p_v7h_bac_mild",
        "_p_v7h_wmt_band",
        "_p_v7h_tsla_mild",
        "_p_v7h_jpm_hotride",
        "_p_v7h_jpm_hotquiet",
        "_p_v7h_xom_mild",
    )
    probes += [
        f"strategies/probes/{p.name}"
        for p in sorted((MOD / "strategies/probes").iterdir())
        if p.name.startswith(keys)
    ]
    if len(sys.argv) > 1:
        probes = ["strategies/flagship_v7h.ms"] + [
            a if a.startswith("strategies") else f"strategies/probes/{a}" for a in sys.argv[1:]
        ]
    print(f"scoring {len(probes)} strategies")
    base = None
    rows = []
    for rel in probes:
        try:
            r = score(rel)
        except Exception as e:
            print(f"ERR {rel}: {e}")
            continue
        rows.append(r)
        if base is None:
            base = r
            print(f"BASE {r['name']} focus {r['focus']} hold {r['hold']}")
            print("  unlocks", r["unlocks"])
            print("  fails", r["focus_f"])
            continue
        d = r["focus_pass"] - base["focus_pass"]
        gained = sorted(set(r["unlocks"]) - set(base["unlocks"]))
        lost = sorted(set(base["unlocks"]) - set(r["unlocks"]))
        mark = "OK" if not r["hold_f"] else "REGRESS"
        print(
            f"{r['name']:40} focus {r['focus']} d={d:+d} hold {r['hold']} [{mark}] "
            f"gained={gained} lost={lost}"
        )
        if r["hold_f"]:
            print("  HOLD", r["hold_f"][:4])
        if d > 0 and not r["hold_f"]:
            print("  *** LIFT ***", gained)
    print("==== lifts only ====")
    for r in rows[1:]:
        d = r["focus_pass"] - base["focus_pass"]
        if d > 0 and not r["hold_f"]:
            gained = sorted(set(r["unlocks"]) - set(base["unlocks"]))
            lost = sorted(set(base["unlocks"]) - set(r["unlocks"]))
            print(f"  +{d} {r['name']} gained={gained} lost={lost}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
