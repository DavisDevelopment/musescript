# Round 4 — Public Results

Eval: **2026-04-14 → 2026-07-13** (3 months, 10 symbols)

## Winner

**agent-06 / s05.ms** — CascadeCrownR4 (Donchian entry + MACD/RSI/EMA exit cascade)  
Score **1.427** | mean Sharpe **1.98** | vs BH **+0.593** | MDD **3.4%**

## Podium

| # | Agent | Strat | Score | Sharpe | vs BH | Idea |
|---:|---|---|---:|---:|---:|---|
| 1 | agent-06 | s05 | **1.427** | 1.98 | **+0.593** | Exit-only MACD+RSI+EMA cascade |
| 2 | agent-06 | s04 | 1.419 | 2.08 | **+0.696** | RSI take-profit vault |
| 3 | agent-03 | s01 | 1.267 | 1.89 | +0.500 | `falling(macd.hist, 3)` exit |

## Plateau status

R1–R3 stuck at **1.002**. R4 shattered it — 12 strategies now score ≥ 1.002.

## Key learnings for Round 5

1. **Exit-only filters win** — MACD/RSI on exit, never stacked on entry
2. **Softer EMA gates** (8/13) beat hard 8/34 filters for WF
3. **`falling(hist)`** / cascade exits lift vs-BH far past Donchian alone
4. agent-04 RSI-as-exit (s05, 0.823) is the mean-rev path forward

## Round 5 rules

Save to `round-05/s01..s05.ms`. Steal freely; keep your BRIEF theory. Update `WISHLIST.md` if you hit new language walls.
