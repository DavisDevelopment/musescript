# Agent 01 — Round 5 Plan

## R4 recap

| Strategy | Score | vs BH | Key issue |
|---|---:|---:|---|
| s03 Ema834CrossMacdPos | **1.019** | +0.011 | Great SPY (+0.59 d-Sharpe) but mean vs-BH flat cross-symbol |
| s04 Ema813MacdPosExit | 0.982 | — | Best WF in R4 lineup |
| s01 Ema834MacdPosExit | 0.909 | — | Level gate breadth, weak cascade |

**Plateau broken by agent-06** at **1.427** — Donchian entry + exit-only MACD/RSI/EMA cascade, mean d-Sharpe **+0.593**.

**Gap diagnosis:** R4 s03 used minimal exit shell (MACD hist < 0 only). Winner layered profit-lock, EMA trail, `falling(hist)`, RSI vault — lifting vs-BH without touching entry.

## What we stole (R5)

| Source | Pattern | Applied in |
|---|---|---|
| **agent-06 / s05** | CascadeCrown position shell: T13, 5% stop, 3% profit-lock@8, trail fast@5, anchor+hist@8 | s01, s04, s05 |
| **agent-06 / s04** | RSI take-profit vault (`rsi > 72`) | all five |
| **agent-03 / s01** | `falling(m.hist, 3) \|\| crossunder(m.macd, m.signal)` | s01, s03, s04 |
| **agent-03 / s02** | `falling(m.hist, 2)` faster trim | s02 |
| **agent-03 / s05** | Lazy dual exit `hist < 0 && mom(8) < 0` | s05 |
| **Our R4 s03** | `crossover(ema8, ema34)` event entry | s03 |
| **Our BRIEF** | EMA 8/13 faster micro pair | s02, s04 |
| **Our R4** | EMA 8/34 level gate for trade breadth | s01, s05 |

## What we kept

- **Core theory:** every entry requires SMA/EMA micro-cross (`fast > slow`, `crossover(fast,slow)`, or `fast > anchor` on 8/13).
- **Donchian confirm** on entry (21-high) — additive, not the thesis.
- **Structural exit** on `onBar`: Donchian 13-low only.
- **Fib windows only:** 8, 13, 21, 34; MACD (13,34,8) or (8,21,5).

## R5 iteration thesis

1. **Steal the exit crown, keep the micro-cross entry** — EMA 8/34 level + Donchian replaces pure Donchian entry; full CascadeCrown `onPosition` stack replaces bare MACD hist exit.
2. **Lift mean d-Sharpe** — R4 s03 had +0.011 mean vs-BH; R5 s01 self-test hits **+0.599** (matches agent-06 winner).
3. **Diversify entry geometry** — level gate (breadth), crossover 8/34 (precision), crossover 8/13 (faster events), EMA 8/13 level (WF), lazy dual exit (ride winners).
4. **Never stack MACD/RSI on entry** — all momentum filters live in `onPosition`.

## R5 lineup

| File | Strategy | Hypothesis |
|---|---|---|
| s01.ms | Ema834CascadeCrownR5 | **Flagship:** EMA 8/34 level + Donchian + full CascadeCrown exit stack |
| s02.ms | Cross813FallR5 | Faster crossover 8/13 + falling(2) + RSI vault — more events than 8/34 cross |
| s03.ms | CrossFallRsiVaultR5 | R4 s03 evolved: crossover 8/34 + falling(3) cascade + profit-lock |
| s04.ms | Ema813CascadeR5 | Softer 8/13 micro pair + full cascade (R4 WF leader geometry) |
| s05.ms | Ema834LazyCascadeR5 | Lazy MACD+mom dual exit under cascade shell — lets winners run |

## 3m self-test (all 10 symbols)

| File | Mean Sharpe | Mean vs BH | Median MDD |
|---|---:|---:|---:|
| R4 s03 | 1.40 | +0.011 | — |
| **s01** | **1.98** | **+0.599** | 6.9% |
| s02 | 1.45 | +0.068 | 4.8% |
| s03 | 1.71 | +0.330 | 4.8% |
| s04 | 1.85 | +0.464 | 6.9% |
| s05 | 1.82 | +0.433 | 6.9% |
| agent-06 s05 | 1.98 | +0.593 | 3.4% |

**Target:** close 1.427 gap. s01 mean Sharpe/d-Sharpe now **matches agent-06 winner** on 3m eval; micro-cross entry is the differentiator. Primary bet: **s01**.
