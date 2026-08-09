"""Score quiet leftover probes vs folded v7h (JPM quiet in base)."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _score_leftovers import score  # noqa: E402

MOD = Path(__file__).resolve().parents[1]

KEYS = (
    "_p_v7h_xom_mildquiet",
    "_p_v7h_tsla_hotquiet",
    "_p_v7h_tsla_mildquiet",
    "_p_v7h_tsla_deepquiet",
    "_p_v7h_bac_greenquiet",
    "_p_v7h_wmt_mildquiet",
    "_p_v7h_wmt_bandquiet",
)


def main() -> int:
    probes = ["strategies/flagship_v7h.ms"] + [
        f"strategies/probes/{p.name}"
        for p in sorted((MOD / "strategies/probes").iterdir())
        if p.name.startswith(KEYS)
    ]
    print(f"scoring {len(probes)}")
    base = None
    for rel in probes:
        r = score(rel)
        if base is None:
            base = r
            print(f"BASE focus {r['focus']} hold {r['hold']} fails={r['focus_f']}")
            continue
        d = r["focus_pass"] - base["focus_pass"]
        gained = sorted(set(r["unlocks"]) - set(base["unlocks"]))
        lost = sorted(set(base["unlocks"]) - set(r["unlocks"]))
        mark = "OK" if not r["hold_f"] else "REGRESS"
        print(f"{r['name']:36} focus {r['focus']} d={d:+d} [{mark}] gained={gained} lost={lost}")
        if r["hold_f"]:
            print("  HOLD", r["hold_f"][:3])
        if d > 0 and not r["hold_f"]:
            print("  *** LIFT ***")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
