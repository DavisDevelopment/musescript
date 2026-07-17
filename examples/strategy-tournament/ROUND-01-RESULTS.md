# Round 1 — Public Results (agents may read for Round 2+)

Eval: **2026-04-14 → 2026-07-13** (3 months, 10 symbols)

## Winner

**agent-05 / s05.ms** — Donchian 21-high / 13-low + 13-bar time stop  
Score **1.002** | mean Sharpe **1.42** | vs BH **+0.035** | MDD **8.1%**

## Top 10

| # | Agent | Strategy | Score | Sharpe | vs BH | MDD |
|---:|---|---|---:|---:|---:|---:|
| 1 | agent-05 | s05 | 1.002 | 1.42 | +0.035 | 0.081 |
| 2 | agent-01 | s05 | 0.885 | 1.18 | -0.201 | 0.111 |
| 3 | agent-02 | s02 | 0.827 | 1.13 | -0.256 | 0.043 |
| 4 | agent-01 | s02 | 0.784 | 1.08 | -0.301 | 0.124 |
| 5 | agent-03 | s01 | 0.767 | 1.08 | -0.300 | 0.148 |
| 6 | agent-05 | s02 | 0.722 | 1.02 | -0.364 | 0.087 |
| 7 | agent-05 | s01 | 0.679 | 0.98 | -0.401 | 0.069 |
| 8 | agent-06 | s02 | 0.607 | 0.75 | -0.633 | 0.091 |
| 9 | agent-01 | s03 | 0.535 | 0.71 | -0.673 | 0.125 |
| 10 | agent-01 | s04 | 0.499 | 0.66 | -0.725 | 0.107 |

## Stealable patterns (from winning code)

- **Donchian channel breaks** via `high >= highest(high, N)` (not close > highest[1])
- **Asymmetric channels**: wider entry (21) / tighter exit (13)
- **Fib time stops** via `onPosition { when bars_in_trade >= 13: flat() }`
- **EMA 8/34** plain cross (agent-01 s05) — strong SPY, weaker cross-symbol
- **EMA 8/34 + EMA21 gate + 5% stop** (agent-02 s02) — lowest MDD in podium

## Round 2 rules

1. Save v2 strategies to `round-02/s01.ms` … `s05.ms` (do NOT overwrite round-01)
2. Write `PLAN-R2.md` documenting what you stole and what you kept
3. **Core theory must stay** per your BRIEF (micro SMA, EMA trend, MACD, RSI, breakout, or maximalist)
4. You MAY read any agent's `round-01/*.ms` and opponent strategies
5. Self-test on 3-month tapes only

Full detail: `results/round-01/LEADERBOARD.md`
