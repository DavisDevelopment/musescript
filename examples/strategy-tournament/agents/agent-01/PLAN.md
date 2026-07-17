# Agent 01 — Micro Structure Plan

## Hypothesis

Short-horizon trend bursts in liquid ETFs and mega-caps show up as fast SMA/EMA crosses. Micro windows (5–13 fast, 13–21 slow) enter early; crisp exits (cross-under, slower exit MA, Fib time stops, 4–8% equity stops) cap drawdown on the 3-month eval window (~63 bars).

Corpus OOS sweeps favor **EMA 8/13** and **SMA 5/21** with optional **EMA 21 exit** over raw symmetric cross-under. On a tight 3m tape, whipsaw risk is high — variants with `onPosition` time stops (21, 34) and hard stops (5–6%) should improve median MDD without killing trade count.

## Iteration approach

1. **Baseline pair** — SMA 8/13 and EMA 8/13 (symmetric exit) as anchors.
2. **Exit asymmetry** — EMA 8/13 enter, exit on cross-under vs EMA 21 (lets winners run).
3. **Faster entry** — SMA 5/21 with 21-bar time stop (Fib) to shed stale holds.
4. **Risk shell** — EMA 8/13 + 6% equity hard stop + 34-bar time stop.
5. **Trend filter** — EMA 5/13 only when `close > sma(34)` + 21-bar time stop.

Self-test loop (SPY only, official 3m window):

```powershell
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-01/strategies/s0N.ms --symbol SPY
```

Iterate on parse/backtest errors first; then compare SPY 3m Sharpe and pick the five that parse cleanly and diversify entry/exit/risk.

## Risk controls

- Window lengths restricted to Fib ladder: 1,2,3,5,8,13,21,34,55,89.
- `onPosition` only for time stops and equity hard stops (no intrabar magic).
- Long-only; flat on cross-under, filter breach, stop, or max bars in trade.

## Success criteria (3m self-test)

- All five strategies parse and backtest without error on SPY.
- Target: positive SPY 3m Sharpe on at least one variant; prefer lower MDD when Sharpe is similar.
- Final five submitted as `s01.ms` … `s05.ms` with `MANIFEST.json` recording one-line hypothesis + SPY Sharpe.
