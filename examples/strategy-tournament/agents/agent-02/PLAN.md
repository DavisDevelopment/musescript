# Agent 02 — EMA Trend Architect

## Hypothesis

Slower EMA crossover pairs (8/21, 8/34, 13/34) generalize better than micro SMA crosses when gated by a **regime filter** (SMA/EMA 34–55) and wrapped in **`onPosition` risk shells** (Fib time stops 21/34/55, 5–6% equity hard stops). On a tight 62-bar eval tape, trend windows above 55 bars under-trade; filters at 21–55 keep signals alive while still blocking counter-trend entries.

Corpus OOS evidence favors **EMA 8/13 with EMA-21 exit** and **EMA 8/34** as core engines. This slate layers trend gates and position management without abandoning the crossover entry mechanic.

## Iteration approach

1. **Seed** five variants spanning Fib EMA pairs from the brief (8/21, 8/34, 13/34, 8/13+exit) with SMA/EMA trend gates at 21, 34, or 55.
2. **Self-test** each on `eval_3m_SPY.csv` only via `tournament_lab.py --eval` (no full corpus tapes).
3. **Prune** dead strategies (0 trades) by shortening trend windows — 89-period filters fail on 62-bar tapes.
4. **Tune** `onPosition` shells: time stops on Fib ladder (21, 34, 55) and equity stops at 5–6%.
5. **Lock** five distinct hypotheses with SPY 3m Sharpes recorded in `strategies/MANIFEST.json`.

## Risk controls

| Shell | Where used | Rationale |
|---|---|---|
| `bars_in_trade >= 21` | s01, s04 | Cut stale fast crosses after one month |
| `bars_in_trade >= 34` | s03, s05 | Medium hold cap for slower pairs |
| `unrealized_pnl < -0.05 * equity` | s02, s04, s05 | Hard stop on adverse drift |
| `unrealized_pnl < -0.06 * equity` | (dropped s04 variant) | Tested; reverted to 5% |
| Trend gate exit `close < trend` | all | Regime break flattens before signal cross |

## Strategy slate

| ID | Engine | Filter | Risk shell | SPY 3m Sharpe |
|---|---|---|---|---:|
| s01 | EMA 8/21 | SMA 55 | time 21 | 0.59 |
| s02 | EMA 8/34 | EMA 21 | equity 5% | **2.38** |
| s03 | EMA 13/34 | EMA 55 | time 21 | 1.54 |
| s04 | EMA 8/13 → exit 21 | EMA 55 | equity 5% + time 21 | 0.78 |
| s05 | EMA 8/13 | EMA 21 | equity 5% + time 34 | 1.85 |

**Best SPY self-test:** `s02` (Sharpe 2.38, +0.08 vs buy-hold, MDD 2.9%, 2 trades).

## Out-of-scope (tournament lock)

- No reads of other agents' folders.
- No scoring on tapes longer than 3 months during iteration.
- Walk-forward and multi-symbol mean Sharpe left to organizer `--score-all`.
