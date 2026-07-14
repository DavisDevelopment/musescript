#!/usr/bin/env python3
"""Fetch real daily OHLCV and write a concatenated MuseScript tape CSV.

Uses yfinance. Install:  .venv/Scripts/pip install yfinance

Default: several liquid US equities, max history available → one long tape.
"""
from __future__ import annotations

import argparse
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT_DEFAULT = ROOT / "data" / "real" / "tape.csv"


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--tickers",
        default="SPY,QQQ,IWM,AAPL,MSFT,GOOGL,AMZN,META,NVDA,JPM,XOM,TSLA,AMD,BAC,WMT",
        help="Comma-separated Yahoo tickers",
    )
    ap.add_argument("--out", type=Path, default=OUT_DEFAULT)
    ap.add_argument("--period", default="max", help="yfinance period (e.g. max, 10y, 5y)")
    args = ap.parse_args()

    try:
        import yfinance as yf
    except ImportError:
        print("Installing yfinance into current interpreter...")
        import subprocess, sys

        subprocess.check_call([sys.executable, "-m", "pip", "install", "yfinance"])
        import yfinance as yf

    tickers = [t.strip().upper() for t in args.tickers.split(",") if t.strip()]
    rows: list[str] = ["symbol,date,open,high,low,close,volume"]
    total = 0
    for t in tickers:
        print(f"download {t} period={args.period} ...")
        df = yf.download(t, period=args.period, interval="1d", auto_adjust=True, progress=False)
        if df is None or df.empty:
            print(f"  skip {t}: empty")
            continue
        # Flatten possible MultiIndex columns from newer yfinance
        if hasattr(df.columns, "get_level_values") and getattr(df.columns, "nlevels", 1) > 1:
            df.columns = [str(c[0]).lower() if isinstance(c, tuple) else str(c).lower() for c in df.columns]
        else:
            df.columns = [str(c).lower() for c in df.columns]
        need = ["open", "high", "low", "close", "volume"]
        for col in need:
            if col not in df.columns:
                raise SystemExit(f"{t}: missing column {col}; got {list(df.columns)}")
        n = 0
        for ts, row in df.iterrows():
            date = ts.strftime("%Y-%m-%d") if hasattr(ts, "strftime") else str(ts)[:10]
            rows.append(
                f"{t},{date},{float(row['open']):.6f},{float(row['high']):.6f},"
                f"{float(row['low']):.6f},{float(row['close']):.6f},{float(row['volume']):.0f}"
            )
            n += 1
        total += n
        print(f"  {t}: {n} bars")

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(f"wrote {args.out} ({total} bars, {len(tickers)} tickers)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
