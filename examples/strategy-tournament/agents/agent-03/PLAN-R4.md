# Agent 03 — Round 4 Plan (MACD / Momentum Regime)

## R3 recap

| Strategy | Score | Sharpe | vs BH | WF | Key issue |
|---|---:|---:|---:|---:|---|
| s01 MacdDonchianHardStop | **0.948** | 1.46 | **+0.075** | 1.08 | Best vs-BH; WF gap vs winner |
| s04 MacdDonchianExitOnly | 0.948 | 1.46 | +0.075 | 1.08 | Identical to s01 — MACD onBar vs onPosition no diff |
| s02 MacdDonchianEmaGate | 0.909 | 1.44 | +0.050 | 0.93 | EMA gate hurt WF |
| s03 MacdDonchianMomHard | 0.009 | 0.03 | −1.36 | 0.94 | MACD hist **entry** gate blocked breakouts |

**Plateau diagnosis:** R3 s01 beats the Donchian winner on mean Sharpe (1.46 vs 1.42) and vs-BH (+0.075 vs +0.035), but composite score trails **1.002** because walk-forward Sharpe is **1.08 vs 1.61**. Root cause: `m.hist < 0` on `onBar` fires too early, whipsawing IWM (−2.34 d-Sharpe) and degrading OOS stability.

## Breakthrough (R4 probes)

Moving MACD off `onBar` flat and using **momentum-decay** exits in `onPosition`:

| Probe | Score | vs BH | WF | Exit logic |
|---|---:|---:|---:|---|
| R3 s01 (baseline) | 0.948 | +0.075 | 1.08 | `hist < 0` onBar |
| p02 delayed hist | 1.002 | +0.035 | **1.61** | `bars >= 8 && hist < 0` onPosition |
| p08 falling hist(2) | 1.159 | +0.451 | 0.84 | `falling(m.hist, 2)` onPosition |
| p11 fall + cross | 1.204 | +0.517 | 0.85 | `falling(2) \|\| crossunder` |
| **p16 fall3 + cross** | **1.267** | **+0.500** | **1.33** | `falling(3) \|\| crossunder` |

**Key insight:** `falling(m.hist, N)` detects momentum *deceleration* before zero-cross, trimming losers early on 3m tape while preserving Donchian winner WF when combined with signal-line crossunder as backup exit.

## What we stole

| Source | Pattern | Applied in |
|---|---|---|
| **agent-05 / s01** | Donchian 21 entry / 13 exit + T13 + 5% hard stop (winner shell) | all five |
| **agent-03 / s04** | MACD exit **only** in `onPosition`, Donchian structural exit on `onBar` | all five |
| **agent-03 / p02** | Delayed MACD hist exit after 8-bar warmup | s04 |
| **agent-03 / R2 s04** | `crossunder(m.macd, m.signal)` as regime flip | s01, s02 |
| **agent-05 / s02** | Faster 21/8 asymmetric channel | explored in probes (s03 uses 21/13) |

## What we kept (MACD regime theory)

- **Core signal:** MACD `(8, 21, 5)` histogram slope and signal-line cross as momentum regime decay detectors — not binary `hist < 0` on bar open.
- **Entry:** Donchian 21-high breakout, no MACD entry gate (R2 lesson preserved).
- **Exit stack:** Donchian 13-low (structural) → MACD momentum decay (onPosition) → T13 → 5% equity stop.
- **Fib windows only:** 2, 3, 8, 13, 21.

## R4 lineup

| File | Strategy | Hypothesis |
|---|---|---|
| s01.ms | MacdFall3CrossExit | **Primary bet:** 3-bar hist fall OR signal crossunder in onPosition — best composite (1.267) with strong WF |
| s02.ms | MacdHistFallCross | Aggressive 2-bar hist fall + cross — max 3m Sharpe (1.90) and vs-BH (+0.52) |
| s03.ms | MacdHistFall3 | Pure 3-bar hist slope exit — highest WF among fall variants (1.46) |
| s04.ms | MacdDelayedHistExit | Safe anchor: 8-bar warmup then hist < 0 — ties winner score (1.002), WF 1.61 |
| s05.ms | MacdFallNegConfirm | Fall + zero confirm (`falling && hist < 0`) — balanced score/WF tradeoff |

## 10-symbol self-test (2026-04-14 → 2026-07-13)

| File | Score | Sharpe | vs BH | MDD | WF |
|---|---:|---:|---:|---:|---:|
| R3 s01 | 0.948 | 1.46 | +0.075 | 8.4% | 1.08 |
| agent-05 s01 | 1.002 | 1.42 | +0.035 | 8.1% | 1.61 |
| **s01** | **1.267** | **1.89** | **+0.500** | **5.7%** | **1.33** |
| s02 | 1.204 | 1.90 | +0.517 | 7.0% | 0.85 |
| s03 | 1.138 | 1.66 | +0.272 | 5.7% | 1.46 |
| s04 | 1.002 | 1.42 | +0.035 | 8.1% | 1.61 |
| s05 | 1.147 | 1.74 | +0.355 | 8.4% | 1.20 |

**Target:** break 1.002 plateau via MACD momentum-decay exits without abandoning histogram theory. s01 is primary bet; s04 is WF-safe fallback.
