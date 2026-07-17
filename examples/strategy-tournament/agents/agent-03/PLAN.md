# Agent 03 — Momentum Regime Plan

## Hypothesis

On a tight 3-month eval window (~62 daily bars), momentum persistence rewards **staying long** when MACD histogram or a secondary momentum signal agrees with price trend. Naive `hist < 0 → flat` exits whipsaw on bullish tapes and miss ~8% buy-hold gains.

Corpus OOS favors MACD + trend filters on long histories, but the tournament tape is too short for `macd(13,34,8)` warmup (~42 bars). We use faster Fib MACD sets `(8,21,5)` and `(8,13,5)` and a **latch-ride** exit: flat only when **both** MACD histogram and the companion signal turn negative.

## Five strategies

| ID | Name | Entry / hold | Exit |
|---|---|---|---|
| s01 | MacdTrendRide | `hist > 0 \|\| ema(8) > ema(21)` | `hist < 0 && ema(8) < ema(21)` |
| s02 | MomMacdRide | `hist > 0 \|\| mom(8) > 0` | `hist < 0 && mom(8) < 0` |
| s03 | RocMacdRide | `hist > 0 \|\| roc(5) > 0` | `hist < 0 && roc(5) < 0` |
| s04 | MacdRisingRide | `rising(close,2) \|\| hist > 0 \|\| ema(8) > ema(21)` | `falling(close,2) && hist < 0 && ema(8) < ema(21)` |
| s05 | MacdTrendGuard | same as s01 | same + 34-bar time stop + 5% equity stop |

## Iteration approach

1. Start from corpus MACD hist regime; adapt windows to Fib ladder.
2. Self-test on SPY eval only (`2026-04-14..2026-07-13`) via `tournament_lab.py --eval --symbol SPY`.
3. Discovered latch-ride pattern after slow-MACD strategies produced 0–1 trades or negative Sharpe.
4. Layer momentum companions (ROC, MOM, rising close) for diversity while sharing the dual-negative exit.

## Risk controls

- Long-only; no leverage.
- s05 adds `onPosition` time stop (34 bars) and 5% equity hard stop.
- All window lengths on Fibonacci ladder: `2,5,8,13,21,34`.

## SPY self-test results (eval 3m)

| Strategy | Sharpe | d-Sharpe vs BH | MDD | Trades |
|---:|---:|---:|---:|---:|
| s04 MacdRisingRide | **2.30** | **0.00** | 0.045 | 1 |
| s03 RocMacdRide | 1.00 | -1.30 | 0.041 | 7 |
| s01 MacdTrendRide | 0.51 | -1.78 | 0.072 | 5 |
| s05 MacdTrendGuard | 0.51 | -1.78 | 0.072 | 5 |
| s02 MomMacdRide | 0.42 | -1.87 | 0.057 | 5 |

Buy-hold SPY Sharpe: 2.30. Best candidate: **s04** (matches buy-hold on SPY eval).
