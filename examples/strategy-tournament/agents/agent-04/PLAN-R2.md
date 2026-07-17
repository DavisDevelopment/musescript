# Agent 04 — Round 2 Plan (Mean Reversion Ranger)

## R1 post-mortem

| Rank | Strategy | Score | Mean Sharpe | Issue |
|-----:|----------|------:|------------:|-------|
| 14 | s03 | 0.038 | 0.080 | Only positive mean Sharpe; recovery-cross worked |
| 19 | s05 | -0.468 | -0.660 | Cross-down entry too late |
| 24 | s02 | -0.550 | -0.699 | EMA(55) slow to warm on 62-bar tape |
| 27 | s01 | -0.788 | -1.098 | Pure dip exits too slow |
| 29 | s04 | -0.828 | -1.100 | EMA stack + dip rarely aligned |

**Root cause:** RSI dip entries without winner-grade exit discipline. Mean reversion bought weakness but held through trend resumption poorly; no Donchian channel exits or Fib time stops.

## What we stole (Round 1 winners)

| Source | Pattern | Applied in |
|--------|---------|------------|
| **agent-05 / s05** | `high >= highest(high, N)` breakout exit; `low <= lowest(low, 13)` stop; `bars_in_trade >= 13` time stop | s03, s05 |
| **agent-02 / s02** | EMA(8)/EMA(34) stack + EMA(21) trend gate; `unrealized_pnl < -0.05 * equity` hard stop | s02, s05 |
| **agent-01 / s02** | EMA(8)/EMA(13) fast pair; exit on `crossunder(fast, exitMa)` | s04 |
| **agent-01 / s05** | EMA 8/34 momentum alignment as trend filter | s02, s05 |

## What we kept (BRIEF mandate)

- **RSI dip-buy:** `r < 42` entries above trend EMA (s01, s03)
- **RSI recovery cross:** `r > 35 && r[1] <= 35` bounce entries (s02, s04, s05)
- **Trend gate:** no longs below EMA(21) or EMA(34)
- **RSI normalization exits:** take profit at RSI 62–68 (not waiting for full overbought)
- **Hard equity stops:** 5% `unrealized_pnl` floor on all five

## Round 2 lineup

| File | Name | Entry | Exit / risk |
|------|------|-------|-------------|
| `round-02/s01.ms` | RsiDipTimeStop | RSI(13) < 42 dip above EMA(21) | RSI > 65, trend break, **13-bar time stop**, 5% stop |
| `round-02/s02.ms` | RsiRecovery834 | RSI(8) recovery cross + EMA8 > EMA34 + EMA(21) gate | EMA crossunder, RSI > 62, **13-bar + 5% stop** |
| `round-02/s03.ms` | RsiDipDonchianExit | RSI(13) < 42 dip above EMA(34) | **Donchian high break** `highest(high,13)`, RSI > 68, 13-bar + 5% stop |
| `round-02/s04.ms` | RsiRecoveryEma813 | RSI(8) recovery cross above EMA(21) | RSI > 62, **crossunder(fast, EMA21)**, 13-bar + 5% stop |
| `round-02/s05.ms` | RsiCrossDonchianTime | RSI(8) recovery + EMA834 stack + EMA(21) gate | **Donchian low** `lowest(low,13)`, RSI > 65, 13-bar + 5% stop |

## Self-test (3m eval only)

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-04/round-02/s03.ms --symbol SPY
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-04/round-02/s03.ms
```

## R2 self-test results (2026-04-14 → 2026-07-13)

| Strategy | SPY Sharpe | SPY Trades | 10-sym Mean Sharpe | vs R1 best |
|----------|----------:|----------:|-------------------:|-----------:|
| s03 | **1.45** | 2 | **0.487** | **+0.407** (was 0.080) |
| s02 | 1.03 | 4 | 0.359 | +0.279 |
| s05 | 1.03 | 4 | 0.283 | +0.203 |
| s04 | 0.34 | 4 | 0.210 | +0.130 |
| s01 | 0.00 | 0 | -0.794 | dip-only baseline |

**Best candidate:** `round-02/s03.ms` — RSI dip entry with Donchian high-break take-profit. Stealing winner exit logic lifted 10-symbol mean Sharpe ~6× vs R1.

## Expected posture

- **s03** targets rank improvement via asymmetric exits (buy dip, sell channel breakout).
- **s02/s05** diversify with EMA834 momentum gate on recovery entries.
- **Weakness:** still unlikely to beat pure Donchian trend-following on SPY buy-and-hold in a bull 3m window; edge is lower MDD and MSFT/AMZN single-name wins.
