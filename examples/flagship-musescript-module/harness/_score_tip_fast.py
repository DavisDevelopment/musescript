#!/usr/bin/env python3
"""Fast filter tip-robust probes via leftovers focus grid, then shortlist."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _score_leftovers import score  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    names = sorted((ROOT / "strategies/probes").glob("_p_v7h7_*.ms"))
    if len(sys.argv) > 1:
        names = [ROOT / a for a in sys.argv[1:]]
    base = score("strategies/flagship_v7h.ms")
    print(
        f"BASE {base['name']}: focus {base['focus']} "
        f"hold_f={len(base['hold_f'])} unlocks={len(base['unlocks'])}"
    )
    ok = []
    for p in names:
        rel = str(p.relative_to(ROOT)).replace("\\", "/")
        r = score(rel)
        regress = bool(r["hold_f"]) or r["focus_pass"] < base["focus_pass"]
        gained = sorted(set(r["unlocks"]) - set(base["unlocks"]))
        lost = sorted(set(base["unlocks"]) - set(r["unlocks"]))
        mark = "REGRESS" if regress else "OK"
        print(
            f"{mark} {r['name']:40} focus {r['focus']} "
            f"gained={gained} lost={lost}"
        )
        if r["hold_f"]:
            print("  HOLD", r["hold_f"][:6])
        if r["focus_f"] and lost:
            print("  FOCUS_F", r["focus_f"][:6])
        if not regress:
            ok.append(rel)
    print("SHORTLIST", len(ok))
    for s in ok:
        print(" ", s)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
