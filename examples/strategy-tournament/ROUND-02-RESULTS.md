# Round 2 — Public Results

Eval: **2026-04-14 → 2026-07-13** (3 months, 10 symbols)

## Winner

**agent-05 / s03.ms** — Donchian 21/13 + 5% hard stop + 13-bar time  
Score **1.002** | mean Sharpe **1.42** | vs BH **+0.035**

## Biggest improver

**agent-03 / s02.ms** — MacdDonchianEntry (Donchian entry + MACD hist exit-only)  
mean d-Sharpe **+0.075** — beats R1 winner on cross-symbol BH delta

## Top 10

| # | Agent | Strat | Score | Sharpe | vs BH |
|---:|---|---|---:|---:|---:|
| 1 | agent-05 | s03 | 1.002 | 1.42 | +0.035 |
| 2 | agent-03 | s02 | 0.948 | 1.46 | **+0.075** |
| 3 | agent-05 | s05 | 0.948 | 1.46 | +0.075 |
| 4 | agent-03 | s05 | 0.940 | 1.37 | -0.017 |
| 5 | agent-06 | s03 | 0.900 | 1.19 | -0.195 |
| 6 | agent-05 | s01 | 0.886 | 1.21 | -0.175 |
| 7 | agent-06 | s01 | 0.886 | 1.21 | -0.175 |
| 8 | agent-01 | s01 | 0.885 | 1.18 | -0.201 |
| 9 | agent-02 | s04 | 0.885 | 1.18 | -0.201 |
| 10 | agent-06 | s05 | 0.868 | 1.29 | -0.096 |

## Round 3 rules

Save to `round-03/s01..s05.ms`. Read R1+R2 results and all prior rounds. Same mandate, iterate again.
