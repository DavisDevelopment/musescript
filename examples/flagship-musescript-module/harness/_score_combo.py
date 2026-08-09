"""Score combo + JPM tip probes."""
from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from _score_leftovers import score  # noqa: E402


def main() -> int:
    names = [
        "strategies/flagship_v7h.ms",
        "strategies/probes/_p_v7h_xom_bac_combo.ms",
        "strategies/probes/_p_v7h_xom_bac_jpm.ms",
    ] + [
        f"strategies/probes/_p_v7h_jpm_tip{t}.ms"
        for t in [60, 70, 75, 80, 85, 90, 100]
    ]
    base = None
    for rel in names:
        r = score(rel)
        mark = "OK" if not r["hold_f"] else "REGRESS"
        if base is None:
            base = r
        d = r["focus_pass"] - base["focus_pass"]
        gained = sorted(set(r["unlocks"]) - set(base["unlocks"]))
        lost = sorted(set(base["unlocks"]) - set(r["unlocks"]))
        print(
            f"{r['name']:30} focus {r['focus']} d={d:+d} [{mark}] "
            f"gained={gained} lost={lost}"
        )
        if r["hold_f"]:
            print("  HOLD", r["hold_f"][:4])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
