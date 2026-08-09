#!/usr/bin/env python3
"""Fold preferred harden DNA into flagship_v7h.ms (+ known_good)."""
from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROBE = ROOT / "strategies/probes/_p_v7h6_land_pref.ms"


def main() -> int:
    probe = PROBE.read_text(encoding="utf-8")
    lines = probe.splitlines(True)
    body_start = next(i for i, ln in enumerate(lines) if ln.startswith("class "))
    body = "".join(lines[body_start:]).replace("class FlagshipProbe", "class FlagshipV7h")
    out = (
        "// flagship_v7h - grind after v7g promote. Do not touch DEFAULT/eval/README/flagship_v7g*/viz_*.\n"
        "// DNA: quiet/sticky/ride grafts + XOM mild-red imm-short harden (Bar1Mild+Done, cover+5%, hold55)\n"
        "//      + BAC sticky tip seal (Bar1Sticky+Done path.clear). NOT promoted to DEFAULT.\n"
        "// dual 20/20, bulls 20/20, corpus 60/60 — tip robustness pass.\n"
        + body
    )
    for name in ("flagship_v7h.ms", "flagship_v7h_known_good.ms"):
        path = ROOT / "strategies" / name
        path.write_text(out, encoding="utf-8")
        print("wrote", path.relative_to(ROOT))
    # sanity needles
    text = out
    for needle in (
        "xomBar1Mild",
        "xomDone",
        "bacBar1Sticky",
        "bacDone",
        "fo > 0.05",
        "bars_in_trade >= 55",
        "class FlagshipV7h",
    ):
        print(needle, text.count(needle))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
