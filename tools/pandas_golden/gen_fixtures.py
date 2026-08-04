#!/usr/bin/env python3
"""Generate muse.pd M1 golden JSON fixtures (no pandas required).

Semantics match fund_panel_loader._forward_fill_onto_bars /
pandas.merge_asof(direction=\"backward\"): last right value with
right_time <= left_time; NaN before the first qualifying right point.
"""

from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
FIX = ROOT / "fixtures"


def forward_fill(bar_times: list[float], points: list[tuple[float, float]]) -> list[float]:
    out = [float("nan")] * len(bar_times)
    if not points:
        return out
    pi = 0
    cur = float("nan")
    for bi, t in enumerate(bar_times):
        while pi < len(points) and points[pi][0] <= t:
            cur = points[pi][1]
            pi += 1
        out[bi] = cur
    return out


def jsonable(xs: list[float]) -> list[float | None]:
    return [None if (isinstance(x, float) and x != x) else x for x in xs]


def write(name: str, payload: dict) -> None:
    FIX.mkdir(parents=True, exist_ok=True)
    path = FIX / name
    path.write_text(json.dumps(payload, indent=2, allow_nan=False) + "\n", encoding="utf-8")
    print("wrote", path)


def main() -> None:
    # Case A — single series asof (filing_date <= bar_date)
    bars = [1.0, 2.0, 3.0, 4.0, 5.0]
    facts = [(2.0, 10.0), (4.0, 20.0)]
    write(
        "merge_asof_backward.json",
        {
            "left_time": bars,
            "right_time": [t for t, _ in facts],
            "right_value": [v for _, v in facts],
            "expected_value": jsonable(forward_fill(bars, facts)),
            "direction": "backward",
            "note": "matches fund_panel_loader._forward_fill_onto_bars",
        },
    )

    # Case B — before first filing → all NaN until filing
    bars2 = [10.0, 11.0, 12.0]
    facts2 = [(11.5, 7.0)]
    write(
        "merge_asof_nan_prefix.json",
        {
            "left_time": bars2,
            "right_time": [t for t, _ in facts2],
            "right_value": [v for _, v in facts2],
            "expected_value": jsonable(forward_fill(bars2, facts2)),
            "direction": "backward",
        },
    )

    # Case C — grouped by symbol codes 1 / 2
    write(
        "merge_asof_by_group.json",
        {
            "left": {
                "time": [1.0, 2.0, 3.0, 1.0, 2.0, 3.0],
                "by": [1.0, 1.0, 1.0, 2.0, 2.0, 2.0],
                "px": [100.0, 101.0, 102.0, 200.0, 201.0, 202.0],
            },
            "right": {
                "time": [1.0, 3.0, 2.0],
                "by": [1.0, 1.0, 2.0],
                "fact": [10.0, 30.0, 20.0],
            },
            "expected_fact": jsonable([
                10.0,  # t=1 group1
                10.0,  # t=2 group1 still 10
                30.0,  # t=3 group1
                float("nan"),  # t=1 group2 — no fact yet
                20.0,  # t=2 group2
                20.0,  # t=3 group2
            ]),
            "direction": "backward",
            "by": "by",
            "on": "time",
        },
    )


if __name__ == "__main__":
    main()
