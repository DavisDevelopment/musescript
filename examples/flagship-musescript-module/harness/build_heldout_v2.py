#!/usr/bin/env python3
"""build_heldout_v2.py -- the multi-regime held-out set broad8mo could never be.

WHY THIS EXISTS
---------------
`tapes/broad8mo/` is 54 symbols over ONE 8-month window (2025-12..2026-08) that
happened to be a strong up-period (mean buy-hold +13.3%). Measured properties of
that set, from harness/gate_stats.py:

  - mean pairwise return correlation 0.126 -> ~7 effective independent bets
  - not one promote/reject decision in the entire flagship thread is resolvable
  - PBO can only be computed over SYMBOLS, never over TIME: 166 bars with a
    34-bar indicator warmup does not admit usable time slices

Time is the dimension that matters. A system tuned on one regime and tested on
one regime learns nothing about the next one. This builds the alternative:
**9 annual folds spanning genuinely different market regimes**, from the local
`equities_daily.db` (1007 symbols, 2.6M bars).

REGIME COVERAGE (this is the whole point)
-----------------------------------------
  2014  grinding up, low vol
  2015  choppy/flat, August vol shock
  2016  January-February drawdown, then recovery
  2017  melt-up, record-low realised vol
  2018  two corrections, negative year
  2019  strong broad rally
  2020  COVID crash and V-shaped recovery
  2021  sustained up
  2022  sustained bear

DATA BOUNDARY -> A FREE SEALED TEST SET
---------------------------------------
The bulk of the universe was fetched through 2023-01-27; a 242-symbol subset
continues to 2026-08. That boundary is exploited rather than papered over:

  WORKING SET  2014-2022, 9 folds, deep universe (866 symbols available)
               -- iterate here, this is where variants get judged
  SEALED SET   2023-01-28 -> 2026-08, 242 symbols
               -- genuinely later in time than every working fold.
               TOUCH ONCE, EVER, ON THE FINAL CANDIDATE. Every look costs a
               multiple-testing haircut (see gate_stats.py section 5), and there
               is no way to un-look.

⚠ SURVIVORSHIP BIAS -- REAL, UNFIXABLE HERE, DO NOT FORGET IT
-------------------------------------------------------------
The universe is symbols present in a *recent* fetch list, pulled retrospectively.
Companies that delisted, went bankrupt, or were acquired between 2014 and 2022
are largely ABSENT. This inflates buy-hold (the benchmark) more than it inflates
a timing strategy, so d_sharpe here is, if anything, CONSERVATIVE for the
strategy -- but returns in absolute terms are optimistic for everything. Any
claim about absolute return from this set is wrong. Comparative paired claims
are the only ones it supports.

Bars are written exactly in the harness tape format (symbol,date,open,high,low,
close,volume). Indicator warmup sits INSIDE each fold, matching how broad8mo and
the rest of the corpus are scored -- the first ~34-63 bars of a fold produce no
trades. Deterministic: same --seed and --universe-size reconstruct the same set,
which matters because `tapes/` is gitignored and only this script is committed.

Usage:
  python harness/build_heldout_v2.py                 # 300-symbol working set
  python harness/build_heldout_v2.py --universe-size 500
  python harness/build_heldout_v2.py --sealed        # also emit the sealed folds
"""
from __future__ import annotations

import argparse
import csv
import json
import random
import sqlite3
import sys
from pathlib import Path

FLAGSHIP = Path(__file__).resolve().parents[1]
DB = FLAGSHIP.parents[3] / "kalshi-ai-advisor" / "python" / "data" / "equities_daily.db"
OUT = FLAGSHIP / "tapes" / "heldout_v2"

WORKING_FOLDS = {
    "2014": ("2014-01-01", "2014-12-31", "grinding up, low vol"),
    "2015": ("2015-01-01", "2015-12-31", "choppy/flat, August vol shock"),
    "2016": ("2016-01-01", "2016-12-31", "Jan-Feb drawdown then recovery"),
    "2017": ("2017-01-01", "2017-12-31", "melt-up, record-low vol"),
    "2018": ("2018-01-01", "2018-12-31", "two corrections, negative year"),
    "2019": ("2019-01-01", "2019-12-31", "strong broad rally"),
    "2020": ("2020-01-01", "2020-12-31", "COVID crash + V recovery"),
    "2021": ("2021-01-01", "2021-12-31", "sustained up"),
    "2022": ("2022-01-01", "2022-12-31", "sustained bear"),
}
SEALED_FOLDS = {
    "sealed_2023h2": ("2023-01-28", "2023-12-31", "SEALED - post-fetch-boundary"),
    "sealed_2024": ("2024-01-01", "2024-12-31", "SEALED"),
    "sealed_2025": ("2025-01-01", "2025-12-31", "SEALED"),
    "sealed_2026": ("2026-01-01", "2026-12-31", "SEALED - partial year"),
}

MIN_BARS = 240
MIN_BARS_SEALED = 150  # 2026 is a partial year


def eligible(con, folds, min_bars) -> set[str]:
    """Symbols with enough bars in EVERY fold -- a balanced panel, so per-fold
    results are comparable and paired tests line up across folds."""
    sets = []
    for name, (lo, hi, _) in folds.items():
        need = MIN_BARS_SEALED if name.startswith("sealed") else min_bars
        rows = con.execute(
            "select symbol from ohlc where date>=? and date<=? "
            "group by symbol having count(*)>=?", (lo, hi, need)).fetchall()
        sets.append({r[0] for r in rows})
    return set.intersection(*sets) if sets else set()


def write_folds(con, folds, universe, out_root: Path) -> dict:
    manifest = {}
    for name, (lo, hi, note) in folds.items():
        d = out_root / name
        d.mkdir(parents=True, exist_ok=True)
        written = {}
        for sym in universe:
            rows = con.execute(
                "select symbol,date,open,high,low,close,volume from ohlc "
                "where symbol=? and date>=? and date<=? order by date",
                (sym, lo, hi)).fetchall()
            if not rows:
                continue
            with (d / f"{sym}.csv").open("w", newline="", encoding="utf-8") as f:
                w = csv.writer(f)
                w.writerow(["symbol", "date", "open", "high", "low", "close", "volume"])
                w.writerows(rows)
            written[sym] = len(rows)
        manifest[name] = {
            "start": lo, "end": hi, "regime": note,
            "symbols": len(written),
            "median_bars": sorted(written.values())[len(written) // 2] if written else 0,
        }
        print(f"  {name:14s} {len(written):4d} symbols  "
              f"{manifest[name]['median_bars']:3d} bars  ({note})", file=sys.stderr)
    return manifest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--universe-size", type=int, default=300,
                    help="symbols to sample for the working set (0 = all eligible)")
    ap.add_argument("--seed", type=int, default=20260807)
    ap.add_argument("--sealed", action="store_true", help="also emit the sealed folds")
    ap.add_argument("--db", default=str(DB))
    args = ap.parse_args()

    dbp = Path(args.db)
    if not dbp.exists():
        print(f"missing db: {dbp}", file=sys.stderr)
        return 2
    con = sqlite3.connect(str(dbp))

    pool = sorted(eligible(con, WORKING_FOLDS, MIN_BARS))
    print(f"eligible across all {len(WORKING_FOLDS)} working folds: {len(pool)} symbols",
          file=sys.stderr)
    if not pool:
        print("no symbols span every fold -- check the db", file=sys.stderr)
        return 2

    rng = random.Random(args.seed)
    universe = sorted(rng.sample(pool, min(args.universe_size, len(pool)))) \
        if args.universe_size else pool
    print(f"working universe: {len(universe)} symbols (seed {args.seed})\n", file=sys.stderr)

    OUT.mkdir(parents=True, exist_ok=True)
    print("working folds:", file=sys.stderr)
    manifest = write_folds(con, WORKING_FOLDS, universe, OUT)

    sealed_manifest, sealed_universe = {}, []
    if args.sealed:
        # Use the FULL sealed pool, not its intersection with the working sample --
        # intersecting throws away most of the only forward data there is. Overlap
        # with the working universe is recorded instead, so paired continuity on the
        # shared names stays available without capping n at the overlap.
        sealed_pool = sorted(eligible(con, SEALED_FOLDS, MIN_BARS_SEALED))
        sealed_universe = sealed_pool
        overlap = len(set(sealed_universe) & set(universe))
        print(f"\nsealed folds ({len(sealed_universe)} symbols, {overlap} shared with "
              f"the working universe):", file=sys.stderr)
        sealed_manifest = write_folds(con, SEALED_FOLDS, sealed_universe, OUT)

    (OUT / "manifest.json").write_text(json.dumps({
        "built_by": "harness/build_heldout_v2.py",
        "source_db": str(dbp),
        "seed": args.seed,
        "universe_size": len(universe),
        "eligible_pool": len(pool),
        "universe": universe,
        "working_folds": manifest,
        "sealed_folds": sealed_manifest,
        "sealed_universe": sealed_universe,
        "caveats": {
            "survivorship": "Universe is symbols present in a recent fetch list, pulled "
                            "retrospectively. Delisted/bankrupt/acquired names from 2014-2022 "
                            "are largely absent. Absolute returns are optimistic for everything; "
                            "only PAIRED comparative claims are supported.",
            "warmup": "Indicator warmup sits inside each fold (first ~34-63 bars trade-free), "
                      "matching broad8mo and the rest of the corpus.",
            "sealed": "sealed_* folds are strictly later in time than every working fold. "
                      "Score them ONCE, on the final candidate only.",
        },
    }, indent=1))
    print(f"\nmanifest: {OUT / 'manifest.json'}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
