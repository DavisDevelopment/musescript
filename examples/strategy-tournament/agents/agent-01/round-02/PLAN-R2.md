# Agent 01 — Round 2 Plan

## What R1 taught us

| Our strategy | Rank | Mean Sharpe | vs BH | MDD | SPY Sharpe |
|---|---:|---:|---:|---:|---:|
| s05 EMA 8/34 | **#2 overall** | 1.18 | -0.20 | 11.1% | 2.30 |
| s02 EMA 8/13 ex21 | #4 | 1.08 | -0.30 | 12.4% | 0.78 |
| s03 EMA 5/21 T21 | #9 | 0.71 | -0.67 | 12.5% | 0.53 |
| s04 EMA 8/13 guard | #10 | 0.66 | -0.73 | 10.7% | 1.43 |
| s01 SMA 8/13 | #22 | -0.71 | -2.09 | 7.6% | 1.12 |

**Core insight:** EMA 8/34 plain cross is our edge on SPY (2.30 Sharpe) but bleeds vs buy-hold cross-symbol (-0.20 mean d-Sharpe). Faster pairs (5/21, 8/13) trade more but whipsaw. Risk shells help MDD but often clip winners on a 63-bar tape.

## What we stole

| Source | Pattern | Applied in |
|---|---|---|
| **agent-05 / s05** (winner) | Fib **13-bar time stop** via `onPosition { bars_in_trade >= 13 }` | s01, s03, s04, s05 |
| **agent-02 / s02** (#3) | **EMA 21 gate** (`close > trend`) + **5% equity hard stop** | s02, s05 |
| **agent-02 / s05** | EMA 8/13 entry + EMA 21 trail exit | s04 (our R1 s02 + T13) |
| **Our R1 s05** | EMA 8/34 micro cross core | all five |

We did **not** pivot to Donchian breakouts — that violates the micro-cross mandate. We borrowed only the **time-stop discipline** and **trend gate / equity stop** shells.

## R2 iteration plan

1. **Keep EMA 8/34 as anchor** — only R1 variant that podiumed.
2. **Layer stolen exits** — 13-bar Fib time stop (agent-05) and EMA 21 gate + 5% stop (agent-02) to improve cross-symbol d-Sharpe and MDD.
3. **Retain one faster pair** — s04 keeps EMA 8/13 enter / EMA 21 exit + T13 for diversification (R1 s02 was #4 multi-symbol).
4. **Avoid over-filtering** — SMA 34 gate on EMA 834 produced zero SPY trades; rejected.

## R2 lineup

| File | Strategy | Hypothesis |
|---|---|---|
| s01.ms | EMA 8/34 + T13 | Winner core + Donchian time discipline |
| s02.ms | EMA 8/34 + EMA21 gate + 5% stop | agent-02 risk shell on our best cross |
| s03.ms | EMA 8/34 + EMA21 gate + T13 | Gate + time stop without equity clip |
| s04.ms | EMA 8/13 ex21 + T13 | Faster micro entry, asymmetric exit |
| s05.ms | EMA 8/34 full stack | Gate + 5% stop + T13 kitchen sink |

## SPY 3m self-test results

```
s01  2.296   (same trades as R1 s05, T13 didn't fire on SPY)
s02  2.379   (+0.08 vs BH, MDD 2.9%)
s03  2.379   (identical to s02 on SPY — gate dominated)
s04  0.778   (more trades, weaker SPY — kept for cross-symbol bet)
s05  2.379   (full stack = gate wins on this tape)
```

**Target for official scoring:** beat our R1 #2 (score 0.885) by lifting mean d-Sharpe via gates/stops while preserving EMA 834 SPY strength.
