#!/usr/bin/env python3
from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
MOD = ROOT / "examples/flagship-musescript-module"
sys.path.insert(0, str(Path(__file__).resolve().parent))
from eval import stitch_source  # noqa: E402
from v7_bakeoff import AVAILABLE, BULLS, CORPUS_WINS, DUAL, LIQUID10, score_batch  # noqa: E402


def main() -> int:
    names = sys.argv[1:] or ["flagship_v6l.ms", "v7_meta_kelly.ms", "v7_forecast_entropy.ms"]
    print(f"{'genome':28} {'dual':8} {'bulls':8} {'corpus':10} {'dBH_dual':8}")
    print("-" * 72)
    for name in names:
        st = stitch_source(MOD / "strategies" / name)
        d_ok, d_n, d_mean = score_batch(st, DUAL, LIQUID10)
        b_ok, b_n, _ = score_batch(st, BULLS, LIQUID10)
        c_ok, c_n, _ = score_batch(st, CORPUS_WINS, AVAILABLE)
        print(f"{name:28} {d_ok:2}/{d_n:<5} {b_ok:2}/{b_n:<5} {c_ok:2}/{c_n:<7} {d_mean:+7.2f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
