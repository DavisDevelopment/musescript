# Agent 03 — Round 7 Plan (Crypto + FX)

## Context

Equity R6 **dual-MACD cascade** (fast + slow MACD both gating entry/exit) transferred poorly to
BTC causal next-open. The cascade over-filters in crypto whipsaw and stalls in FX ranges. Round 7
rebuilds around **one MACD engine per strategy** with domain-appropriate exit layers.

## Hypothesis

1. **Crypto** — momentum is bursty; enter on histogram acceleration (`rising(hist, n)`) and exit
   on delayed slope roll (`falling(hist, n, minBars)`) so next-open lag does not stop out every bar.
2. **Forex** — ranges dominate; MACD zero-line / cross signals need **wider hard stops** (8%) and
   must not require dual MACD agreement.
3. **Fusion** — Donchian breakout entry + MACD histogram exit-only (R2 equity steal) still works on
   BTC/EUR but needs walk-forward care; keep as high-variance slot.

## Strategy lineup

| File | Name | Core MACD | Entry | Exit / risk |
|---|---|---|---|---|
| s01 | MacdHistRegime | 8/21/5 | hist > 0 | hist < 0 + 8% equity stop |
| s02 | MacdCrossMomentum | 8/21/5 | macd × signal cross | crossunder \|\| hist < 0 |
| s03 | MacdRisingEntry | 5/13/8 | rising(hist,3) && hist>0 | falling(hist,3,5) + hard stop |
| s04 | MacdDonchianFusion | 8/21/5 | Donchian 21-high | Donchian 13-low \|\| hist<0 + stmt templates |
| s05 | MacdRisingCascadeExit | 8/21/5 | rising(hist,2) && hist>0 | falling(hist,3,8) + HardStop template |

## Language gifts used

- **Stmt templates:** `TrailingStop`, `TimeStop`, `HardStop` in s04/s05 (gene-runner expansion verified)
- **`falling(hist, n, minBars)`:** s03 (minBars=5), s05 (minBars=8) — avoids immediate whipsaw exits
- **`&&` / `||`:** cascade exits throughout
- **Fib windows only:** 5, 8, 13, 21, 34, 55

## Self-test results (full 10-symbol, next-open)

| Rank | Strat | Score | Mean Sharpe | vs BH | MDD | WF |
|---:|---|---:|---:|---:|---:|---:|
| 1 | s03 | 0.462 | +0.055 | +0.912 | 3.3% | 0.124 |
| 2 | s01 | 0.361 | −0.126 | +0.731 | 4.1% | 0.246 |
| 3 | s05 | 0.107 | −0.502 | +0.355 | 4.1% | 0.185 |
| 4 | s04 | −0.030 | −0.485 | +0.372 | 2.7% | −0.823 |
| 5 | s02 | −0.018 | −0.714 | +0.143 | 4.1% | 0.270 |

**Flagship:** `s03.ms` — best composite score, positive mean Sharpe, strong BTC (+1.81 d-Sharpe).

**Upside bet:** `s04.ms` — BTC Sharpe 1.05, EUR Sharpe 2.08, but walk-forward collapses; keep for
steal-value if organizer weights eval over WF.

## Iteration notes

- `m.hist > 0 && high >= highest(high, n)[1]` never traded — lookback on Donchian blocked entries;
  reverted to R2 pattern (breakout on current window, MACD exit-only).
- Dual MACD (fast + slow) deliberately dropped — single engine + layered exits only.
- FX pairs still drag mean Sharpe; need asset-class param split (wishlist).

## Commands

```powershell
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-03/round-07/s03.ms --symbol BTCUSD
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-03/round-07/s03.ms --symbol EURUSD
```
