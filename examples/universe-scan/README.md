# Universe-scanner strategies (cross-sectional, whole-universe)

Integrated symbol-scanner strategies: each `onBar` scores every live name in the panel
universe (`symbols()`), ranks cross-sectionally, and rebalances a shared portfolio book.
Run over a `PanelFeed` via `MuseRuntime.runPanel(source, bySym, opts)`.

## ⚠️ Backtest honestly: `{ fillNextOpen: true, costBps: 10 }`
Two harness options that separate a real edge from a backtest artifact:
- **`fillNextOpen: true`** — decide at `close[t]`, fill at `open[t+1]`. The default fills at
  `close[t]` using a `close[t]`-derived signal (same-bar lookahead); on the real universe that
  inflated gains ~35% / Sharpe ~17%.
- **`costBps: 10`** — per-side trading cost (commission + spread/slippage) in bps of traded
  notional. Default 0 is frictionless fantasy. 10 bps/side (~20 bps round-trip) is realistic for
  liquid US equities.

## Measured (real equities_daily.db: 1003 symbols, 2013–2026, ~3405 daily bars)

Honest fills throughout. Sharpe shown frictionless → at a realistic 10 bps/side:

| Strategy | 0 bps | **10 bps** | Notes |
|---|---|---|---|
| `strategy-kinds/31_mom_universe_scan` | −0.23 | worse | naive single-factor — loses money |
| `01_trend_momentum` | +0.31 | — | per-name 200-MA trend filter + 6-month momentum |
| `02_multifactor_zscore` | +0.69 | +0.40 | 4-factor cross-sectional z-blend; **turnover kills it under cost** |
| `03_multifactor_hysteresis` | **+0.74** | **+0.53** | 02 + wide-band hysteresis — **the winner net of cost** |

`03` grows 100k → ~360k over 13 years at 10 bps. Turnover is the enemy: `02` rebalances to the
exact top-15 daily (dies at 20 bps); `03` holds a name until it exits the top-45, so trades become
small notional deltas that survive realistic costs. Full-universe backtest ≈ 18 s single-thread;
live per-bar scan of all 1003 names ≈ 3–5 ms.

## Features these showcase
Per-symbol accessors (`mom_of`, `rsi_of`, `sma_of`, `close_of`), cross-sectional stats
(`stat_mean`/`stat_stddev` for z-scoring, `scan_top`), `dict_*`, and the shared portfolio book
(`rebalance_equal`). The winning idea is **decorrelated factor blending** (trend momentum +
short-term reversal + MA-distance + RSI mean-reversion), each z-scored across the universe.

## Notes / gotchas found while building these
- Top-level `function` decls with multiple statements were finicky — inline the logic in `onBar`.
- Arrow lambdas passed to `filter`/`map` work with a **pure-parameter** predicate, but do **not**
  capture outer `onBar`-scope locals (e.g. `filter(picks, s => dict_get(scores, s) > 0)` silently
  matched nothing). Keep lambda bodies self-contained until that's fixed.
- A universe-breadth "risk-off" gate *lowered* Sharpe here (0.69 → 0.63) — the trend filter
  already gates regime implicitly; an explicit gate over-cuts good exposure.
