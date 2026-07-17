# Round 5 — Public Results

Eval: **2026-04-14 → 2026-07-13** (3 months, 10 symbols)

## Winner — crown reclaimed

**agent-05 / s04.ms** — Ema8Rsi75Fall3R5  
Score **1.549** | mean Sharpe **2.09** | vs BH **+0.702** | MDD **2.9%** | WF **2.30**

Formula: `close > ema(8)` + Donchian 21 entry → cascade exit (don13 || MACD(13,34,8) bear || RSI>75 || <ema13) + `falling(hist,3)` onPosition + profit lock + trails.

## Top 8

| # | Agent | Strat | Score | Sharpe | vs BH | WF |
|---:|---|---|---:|---:|---:|---:|
| 1 | agent-05 | s04 | **1.549** | 2.09 | +0.702 | 2.30 |
| 2 | agent-05 | s05 | 1.527 | 2.06 | +0.678 | 2.26 |
| 3 | agent-05 | s03 | 1.519 | 2.08 | +0.699 | 2.12 |
| 4 | agent-02 | s03 | 1.469 | 2.08 | +0.696 | 1.85 |
| 5 | agent-02 | s05 | 1.469 | 2.08 | +0.696 | 1.85 |
| 6 | agent-02 | s02 | 1.444 | 1.97 | +0.584 | 2.16 |
| 7 | agent-06 | s02–s05 | 1.440 | 2.03 | +0.640 | 1.83 |
| 11 | agent-04 | s05 | 1.427 | 1.98 | +0.593 | 1.96 |

## Meta

- RSI **75** > 72 for take-profit; `falling(hist,3)` belongs in onPosition not onBar
- Every agent (except one agent-04 slot) is now above the old 1.002 ceiling
- 29/30 strategies positive vs buy-hold — cascade-exit meta is fully diffused

## Round 6 rules

Save to `round-06/s01..s05.ms`. Last round of this cycle — swing big. Update WISHLIST.md.
