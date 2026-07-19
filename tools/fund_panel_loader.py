#!/usr/bin/env python3
"""
fund_panel_loader.py — Build a MuseScript panel (bySym JSON) from real daily
OHLCV joined with point-in-time SEC/EDGAR fundamentals.

Sources (both from the kalshai repo, read-only):
    kalshi-ai-advisor/python/data/equities_daily.db   — OHLCV, `ohlc` table
    kalshi-ai-advisor/python/data/edgar_facts.duckdb   — `edgar_facts` (financial_metric
                                                          rows) + `edgar_identity` (cik<->ticker)

Output shape matches what `MuseRuntime.runPanel(source, bySym, opts)` /
`PanelFeed.fromSymbolBars` expect:

    { "AAPL": [ {open,high,low,close,volume,time,
                 data: {revenue_fy: <fwd-filled or NaN>, ...}}, ... ],
      "MSFT": [ ... ], ... }

PIT correctness (the one property that matters here): for bar date `d` and
symbol `s`, a fundamental's value is the most recently *filed* value with
filing_date <= d — never period_end/as_of, which is when the number describes
the world, not when the market learned it. A field is `NaN` for every bar
strictly before that symbol's first filing of it. This is a plain per-symbol
merge-forward-fill: facts are pulled sorted by filing_date once per symbol,
then walked in lockstep with the (also sorted) bar-date axis — no fact is
ever consulted before its filing_date, and no future filing can leak
backward. Also emits period-over-period growth series (see `_DERIVED`) for a
"quality on discount" strategy's use, computed only from the two chained raw
facts' own filing dates — a growth number about (period i vs period i-1)
becomes visible no earlier than period i's own filing date.

Usage:
    tools/fund_panel_loader.py --out data/fund_panel.json
    tools/fund_panel_loader.py --covered-only --start 2013-01-02 --end 2026-07-17
    tools/fund_panel_loader.py --symbols AAPL,MSFT,JNJ --fields revenue_fy,net_income_fy
    tools/fund_panel_loader.py --covered-only --limit 50 --out data/fund_panel_small.json

Run with a Python that has duckdb (this repo's .venv has it installed) — no
network access, this only reads the two local databases built by
crawling/xbrl_backfill.py and the existing equities crawler.
"""
from __future__ import annotations

import argparse
import json
import os
import sqlite3
from pathlib import Path
from typing import Optional

import duckdb

ROOT = Path(__file__).resolve().parents[1]                     # muse-script/
KALSHAI_PY = ROOT.parents[1] / "kalshi-ai-advisor" / "python"   # kalshai-ai-advisor/python/
EQUITIES_DB = KALSHAI_PY / "data" / "equities_daily.db"
EDGAR_DB = KALSHAI_PY / "data" / "edgar_facts.duckdb"

# Raw predicates pulled straight from edgar_facts, forward-filled per symbol.
# Curated for a Piotroski-style "quality" read: profitability, cash quality,
# leverage, size. (See kalshi-ai-advisor/python/crawling/xbrl_facts.py for
# the full concept list — this is the useful subset with decent coverage.)
DEFAULT_FIELDS = [
    "revenue_fy",
    "net_income_fy",
    "gross_profit_fy",
    "operating_income_fy",
    "operating_cash_flow_fy",
    "total_assets_fy",
    "total_liabilities_fy",
    "stockholders_equity_fy",
    "long_term_debt_fy",
    "weighted_avg_shares_diluted_fy",
]

# Derived period-over-period growth fields: (output_name, source_predicate).
# growth_i = (val_i - val_{i-1}) / abs(val_{i-1}), visible from period i's own
# filing_date (the later of the two facts chained — i-1 is already known by
# then, so no extra leak is introduced by definition).
_DERIVED = [
    ("revenue_growth", "revenue_fy"),
    ("net_income_growth", "net_income_fy"),
    ("op_cash_flow_growth", "operating_cash_flow_fy"),
]


def _equities_symbols(conn: sqlite3.Connection) -> list[str]:
    return [r[0] for r in conn.execute("SELECT DISTINCT symbol FROM ohlc ORDER BY symbol").fetchall()]


def _load_bars(conn: sqlite3.Connection, symbol: str, start: str, end: str) -> list[dict]:
    rows = conn.execute(
        "SELECT date, open, high, low, close, volume FROM ohlc "
        "WHERE symbol = ? AND date >= ? AND date <= ? ORDER BY date",
        (symbol, start, end),
    ).fetchall()
    out = []
    for date, o, h, l, c, v in rows:
        # Session time as an integer YYYYMMDD key (matches PanelFeed.fromSymbolBars'
        # Bar.time-keyed alignment used throughout the existing universe-scan examples).
        t = int(str(date).replace("-", "")[:8])
        out.append({"date": date, "time": t, "open": o, "high": h, "low": l, "close": c, "volume": v})
    return out


def _ticker_cik_map(edgar: duckdb.DuckDBPyConnection, symbols: list[str]) -> dict[str, str]:
    rows = edgar.execute(
        "SELECT DISTINCT ticker, cik FROM edgar_identity WHERE ticker != ''"
    ).fetchall()
    m: dict[str, str] = {}
    for ticker, cik in rows:
        if ticker in symbols and ticker not in m:
            m[ticker] = cik
    return m


def _facts_for_cik(edgar: duckdb.DuckDBPyConnection, cik: str, predicates: list[str]) -> dict[str, list[tuple[str, float]]]:
    """{predicate: [(filing_date, value_num), ...]} sorted by filing_date, dedup by keeping
    the latest-filed value per (predicate, as_of) — mirrors financials_pivot_as_known's
    "prefer latest filed_at" rule but keeps the whole PIT series instead of one snapshot."""
    if not predicates:
        return {}
    ph = ",".join(["?"] * len(predicates))
    rows = edgar.execute(
        f"""SELECT predicate, filing_date, as_of, value_num
            FROM edgar_facts
            WHERE cik = ? AND fact_type = 'financial_metric'
              AND predicate IN ({ph})
              AND value_num IS NOT NULL AND filing_date != ''
              AND (superseded_at IS NULL OR superseded_at = '')
            ORDER BY predicate, filing_date""",
        [cik, *predicates],
    ).fetchall()
    out: dict[str, dict[str, tuple[str, float]]] = {}
    for predicate, filing_date, as_of, value_num in rows:
        by_period = out.setdefault(predicate, {})
        prev = by_period.get(as_of)
        if prev is None or filing_date > prev[0]:
            by_period[as_of] = (filing_date, float(value_num))
    series: dict[str, list[tuple[str, float]]] = {}
    for predicate, by_period in out.items():
        pts = sorted(by_period.values(), key=lambda p: p[0])  # sort by filing_date
        series[predicate] = pts
    return series


def _growth_series(raw: list[tuple[str, float]]) -> list[tuple[str, float]]:
    """Period-over-period % growth, keyed by the LATER fact's own filing_date."""
    out = []
    for i in range(1, len(raw)):
        prev_val = raw[i - 1][1]
        cur_date, cur_val = raw[i]
        if prev_val == 0:
            continue
        out.append((cur_date, (cur_val - prev_val) / abs(prev_val)))
    return out


def _forward_fill_onto_bars(bar_dates: list[str], points: list[tuple[str, float]]) -> list[float]:
    """Merge-forward-fill sorted (filing_date, value) points onto sorted bar_dates.
    NaN for every bar strictly before points[0]'s filing_date."""
    out = [float("nan")] * len(bar_dates)
    if not points:
        return out
    pi = 0
    cur = float("nan")
    for bi, d in enumerate(bar_dates):
        while pi < len(points) and points[pi][0] <= d:
            cur = points[pi][1]
            pi += 1
        out[bi] = cur
    return out


def build_panel(
    symbols: list[str],
    *,
    start: str,
    end: str,
    fields: list[str],
    with_growth: bool = True,
    equities_db: Path = EQUITIES_DB,
    edgar_db: Path = EDGAR_DB,
) -> tuple[dict[str, list[dict]], dict[str, int]]:
    """Returns (bySym, coverage) where coverage[symbol] = number of non-NaN aux datapoints."""
    sconn = sqlite3.connect(str(equities_db))
    econn = duckdb.connect(str(edgar_db), read_only=True)
    try:
        cik_map = _ticker_cik_map(econn, symbols)
        derived_sources = sorted({src for _, src in _DERIVED if with_growth})
        all_predicates = sorted(set(fields) | derived_sources)

        bySym: dict[str, list[dict]] = {}
        coverage: dict[str, int] = {}
        for sym in symbols:
            bars = _load_bars(sconn, sym, start, end)
            if not bars:
                continue
            bar_dates = [b["date"] for b in bars]

            cik = cik_map.get(sym)
            raw_series: dict[str, list[tuple[str, float]]] = {}
            if cik:
                raw_series = _facts_for_cik(econn, cik, all_predicates)

            filled: dict[str, list[float]] = {}
            for f in fields:
                filled[f] = _forward_fill_onto_bars(bar_dates, raw_series.get(f, []))
            if with_growth:
                for out_name, src in _DERIVED:
                    g = _growth_series(raw_series.get(src, []))
                    filled[out_name] = _forward_fill_onto_bars(bar_dates, g)

            n_nonnan = 0
            out_bars = []
            for i, b in enumerate(bars):
                data = {}
                for f, series in filled.items():
                    v = series[i]
                    if v == v:  # not NaN
                        n_nonnan += 1
                    data[f] = v
                out_bars.append({
                    "open": b["open"], "high": b["high"], "low": b["low"],
                    "close": b["close"], "volume": b["volume"], "time": b["time"],
                    "data": data,
                })
            bySym[sym] = out_bars
            coverage[sym] = n_nonnan
        return bySym, coverage
    finally:
        sconn.close()
        econn.close()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--symbols", default="", help="Comma-separated tickers (default: full equities universe)")
    ap.add_argument("--covered-only", action="store_true",
                     help="Only symbols that have a CIK mapping AND >=1 financial_metric fact")
    ap.add_argument("--limit", type=int, default=0, help="Cap symbol count (0 = no cap)")
    ap.add_argument("--start", default="2013-01-02")
    ap.add_argument("--end", default="2026-07-17")
    ap.add_argument("--fields", default=",".join(DEFAULT_FIELDS))
    ap.add_argument("--no-growth", action="store_true", help="Skip derived YoY growth fields")
    ap.add_argument("--out", default=str(ROOT / "data" / "fund_panel.json"))
    args = ap.parse_args()

    sconn = sqlite3.connect(str(EQUITIES_DB))
    all_symbols = _equities_symbols(sconn)
    sconn.close()

    if args.symbols:
        symbols = [s.strip().upper() for s in args.symbols.split(",") if s.strip()]
    else:
        symbols = all_symbols

    if args.covered_only:
        econn = duckdb.connect(str(EDGAR_DB), read_only=True)
        cik_map = _ticker_cik_map(econn, symbols)
        have_fin = {r[0] for r in econn.execute(
            "SELECT DISTINCT cik FROM edgar_facts WHERE fact_type='financial_metric'"
        ).fetchall()}
        econn.close()
        symbols = [s for s in symbols if cik_map.get(s) in have_fin]

    if args.limit:
        symbols = symbols[: args.limit]

    fields = [f.strip() for f in args.fields.split(",") if f.strip()]
    print(f"Building panel: {len(symbols)} symbols, {args.start}..{args.end}, "
          f"fields={fields}, growth={not args.no_growth}")

    bySym, coverage = build_panel(
        symbols, start=args.start, end=args.end, fields=fields, with_growth=not args.no_growth,
    )

    covered_symbols = sum(1 for n in coverage.values() if n > 0)
    total_bars = sum(len(v) for v in bySym.values())
    print(f"{len(bySym)} symbols with OHLCV, {covered_symbols} with >=1 non-NaN aux datapoint, "
          f"{total_bars} total bars")

    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        json.dump(bySym, f)
    print(f"wrote {out_path} ({out_path.stat().st_size / 1e6:.1f} MB)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
