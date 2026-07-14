# OHLCV data for MuseScript indicator stress

## Real tape

```powershell
.\run.ps1 fetch-ohlcv
```

Writes `data/real/tape.csv` — concatenated daily bars from liquid US tickers via yfinance.

## Synthetic

Example 08 builds a large synthetic tape in-memory (`BarFeed.synthetic`).
