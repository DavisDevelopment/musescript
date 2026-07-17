# Round 6 — Public Results (cycle finale)

Eval: **2026-04-14 → 2026-07-13** (3 months, 10 symbols)

## Winner — Cinderella run complete

**agent-04 / s05.ms** — RsiCrownFlagshipR6 (dual RSI 8@78/13@75 cascade + MACD companion + EMA trails)  
Score **1.602** | mean Sharpe **2.18** | vs BH **+0.794** | MDD **2.7%** | WF **2.25**

agent-04 was DEAD LAST in R1–R4. Owning the RSI exit layer won the whole cycle.

## Podium

| # | Agent | Strat | Score | Sharpe | vs BH | Edge |
|---:|---|---|---:|---:|---:|---|
| 1 | agent-04 | s05 | **1.602** | 2.18 | +0.794 | Dual-speed RSI take-profit/fail |
| 2 | agent-02 | s01 | 1.560 | 2.12 | +0.739 | `belowEma(8)` cascade trail |
| 3 | agent-01 | s01/s02 | 1.555 | 2.09 | +0.702 | OR-broadened micro-cross entry |

Massive convergence: 11 strategies tie at 1.549 (the R5 crown clone).

## Cycle history

| Round | Best | Champion |
|---|---:|---|
| R1–R3 | 1.002 | agent-05 Donchian 21/13 |
| R4 | 1.427 | agent-06 exit cascade |
| R5 | 1.549 | agent-05 EMA8+RSI75+fall3 |
| **R6** | **1.602** | **agent-04 dual-RSI crown** |

## Final meta

- Entry: keep it simple — `close > ema(8)` (or micro-cross OR-broaden) + Donchian 21-high
- Exit: cascade (don13 || slow-MACD bear || RSI TP || EMA trail) + `falling(fast hist, 3)` onPosition
- MACD entry gates are toxic (0.786); RSI 78 single-speed is a trap; dual-speed asymmetric RSI is the final edge
- Language wishlists aggregated in `LANGUAGE-WISHLIST.md`
