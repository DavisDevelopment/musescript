# Agent 03 — Round 2 Plan (MACD / Momentum Regime)

## R1 recap

| Strategy | R1 rank | mean Sharpe | vs BH | Notes |
|---|---:|---:|---:|---|
| s01 MacdTrendRide | **#5 overall** | 1.08 | -0.30 | Best in-house; hist + EMA latch |
| s02 MacdMomLatch | #28 | -1.09 | -2.47 | Mom exit too slow on 3m tape |
| s03 MacdHistLatch | #30 | -1.48 | -2.87 | EMA34 gate over-filters entries |
| s04 MacdCrossMom | #26 | -0.78 | -2.16 | Cross entries sparse on 62 bars |
| s05 MacdRisingGuard | #15 | -0.17 | -1.56 | Rising filter → near-zero trades |

**Key R1 lesson:** Pure MACD regime works (#5) but needs opponent risk shells to compete with Donchian winner.

## What we stole (opponent logic)

| Source | Pattern stolen | Applied in |
|---|---|---|
| **agent-05 s05** (#1) | Donchian `high >= highest(high, 21)` entry, `low <= lowest(low, 13)` exit | s02, s05 |
| **agent-05 s05** | 13-bar Fib time stop via `onPosition` | s01, s02, s03, s05 |
| **agent-05 s02** | Faster 13-high / 8-low asymmetric channels | s03 |
| **agent-02 s02** (#3) | 5% equity hard stop `unrealized_pnl < -0.05 * equity` | s05 |
| **agent-02 s02** | EMA(21) trend gate on entries | explored in s03 draft (rejected — hurt SPY) |
| **agent-01 s05** (#2) | EMA 8/34 stack as momentum confirmation | s04 fast/slow filter |

## What we kept (MACD regime theory)

- **Core signal:** MACD `(8, 21, 5)` histogram as momentum regime filter
- **Entry philosophy:** MACD hist > 0 OR Donchian break with MACD exit (not both required on entry — critical insight from iteration)
- **Exit philosophy:** `hist < 0` as regime flip; layered with Donchian low breaks and momentum (`mom`) confirmation
- **s04:** MACD line/signal crossover + EMA 8/13 stack — pure cross-regime variant for ladder diversity

## Round 2 ladder

| ID | Name | Entry | Exit / risk |
|---|---|---|---|
| s01 | MacdTrendTime13 | `hist > 0 \|\| ema8 > ema21` (R1 s01) | `hist < 0 && ema8 < ema21` + **13-bar time stop** |
| s02 | MacdDonchianEntry | **Donchian 21-high** (no MACD gate) | Donchian 13-low **or** `hist < 0` + 13-bar time stop |
| s03 | MacdDonchian13x8 | Donchian 13-high | Donchian 8-low or `hist < 0` + 13-bar time stop |
| s04 | MacdCrossMom | `crossover(macd, signal) && ema8 > ema13` | `crossunder` + `mom(5) < 0` |
| s05 | MacdDonchianMomExit | Donchian 21-high | 13-low or (`hist < 0 && mom(8) < 0`) + 13-bar + **5% stop** |

## R2 self-test (3m eval, 2026-04-14..2026-07-13)

| ID | SPY Sharpe | SPY vs BH | 10-sym mean Sharpe | 10-sym vs BH |
|---|---:|---:|---:|---:|
| s01 | 0.51 | -1.78 | 1.08 | -0.30 |
| **s02** | **2.54** | **+0.25** | **1.46** | **+0.07** |
| s03 | 2.54 | +0.25 | 1.25 | -0.14 |
| s04 | -0.83 | -3.13 | -0.78 | -2.16 |
| s05 | 2.00 | -0.29 | 1.37 | -0.02 |

**Best candidate: s02** — positive mean d-Sharpe vs buy-hold across 10 symbols (+0.07), beating R1 #5 and approaching tournament winner (+0.035).

## Design insight

Donchian entry timing (stolen from agent-05) + MACD histogram as **exit regime filter** (not entry gate) is the winning hybrid. Requiring `hist > 0` on entry blocked too many breakouts on the 62-bar window.
