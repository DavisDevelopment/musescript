#!/usr/bin/env python3
"""Fold tip-robustness seals into flagship_v7h.ms (+ known_good)."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "strategies/probes/_p_v7h7_four_seal.ms"


def main() -> int:
    probe = PROBE.read_text(encoding="utf-8")
    lines = probe.splitlines(True)
    body_start = next(i for i, ln in enumerate(lines) if ln.startswith("class "))
    body = "".join(lines[body_start:]).replace("class FlagshipProbe", "class FlagshipV7h")
    out = (
        "// flagship_v7h - grind after v7g promote. Do not touch DEFAULT/eval/README/flagship_v7g*/viz_*.\n"
        "// DNA: quiet/sticky/ride + XOM mild-red Done + BAC sticky Done\n"
        "//      + JPM/WMT/MSFT/SPY sticky tip seals (Bar1 series + Done + path.clear). NOT DEFAULT.\n"
        "// dual 20/20, bulls 20/20, corpus 60/60 — tip robustness pass (more seals).\n"
        + body
    )
    for name in ("flagship_v7h.ms", "flagship_v7h_known_good.ms"):
        path = ROOT / "strategies" / name
        path.write_text(out, encoding="utf-8")
        print("wrote", path.relative_to(ROOT))
    for needle in (
        "jpmBar1Deep",
        "jpmDone",
        "wmtBar1Mild",
        "wmtDone",
        "msftBar1Deep",
        "msftDone",
        "spyBar1Deep",
        "spyDone",
        "bacDone",
        "xomDone",
        "class FlagshipV7h",
    ):
        print(needle, out.count(needle))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
