# Agent 05 — Breakout Hunter Plan

## Hypothesis

Volatility contraction precedes directional expansion. On the fixed 3-month eval window (~62 daily bars), Donchian channel breakouts should capture momentum bursts. MuseScript `highest`/`lowest` include the current bar, so entries use `high >= highest(high, N)` and exits use `low <= lowest(low, N)` for valid breakouts.

## Strategy ladder (5 variants)

| ID | Entry | Filter | Exit | Risk |
|---|---|---|---|---|
| s01 | `high >= highest(high, 21)` | none | `low <= lowest(low, 8)` | channel only (BRIEF seed) |
| s02 | `high >= highest(high, 13)` | none | `low <= lowest(low, 5)` | faster channel for short tape |
| s03 | `high >= highest(high, 21)` | `atr(8) < atr(21) * 0.98` | `low <= lowest(low, 8)` | mild ATR squeeze |
| s04 | `high >= highest(high, 13)` | `atr(5) < atr(13) * 0.98` | `low <= lowest(low, 5)` | fast squeeze + 5% stop |
| s05 | `high >= highest(high, 21)` | none | `low <= lowest(low, 13)` | 13-bar time stop |

## Iteration approach

1. Anchor on BRIEF Donchian 21/8 baseline (s01).
2. Shorten channel to 13/5 for more signals in 62-bar window (s02).
3. Gate on mild ATR compression — strict 13/55 × 0.85 yields zero trades on 3m tapes (s03).
4. Pair fast squeeze with hard equity stop for high-beta names (s04).
5. Widen exit channel and cap hold time to reduce stale positions (s05).

## Risk controls

- Long-only; flat when channel or filter fails.
- s04: `onPosition` 5% equity hard stop.
- s05: 13-bar time stop.
- All window lengths on Fib ladder: 5, 8, 13, 21.

## Self-test

```powershell
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-05/strategies/s01.ms --symbol SPY
```

Repeat for s02–s05.
