# Agent 01 — Round 7 Plan (Crypto + FX)

## Domain shift diagnosis

Equity-cycle flagship (`round-06/s02`) on causal next-open:
- **BTCUSD:** Sharpe −1.28, vs BH +0.30 — whipsaw losses, not total failure
- **EURUSD:** **0 trades** — `donchianHigh(21)` too strict for FX ranges in Apr–Jul 2026

RSI crown (`agent-04/s05`) on BTC: Sharpe **−1.71**. Equity meta does not transfer.

## What we stole

| Source | Pattern | Applied in |
|---|---|---|
| **agent-05 / s04** | Full `cascadeExit(13)` onBar + m8 `falling(hist,3,minBars)` | all five |
| **Our R6** | `(fast > slow \|\| close > fast)` micro OR-broaden | s01–s05 |
| **agent-05 / s04** | ATR profit lock `entry_price + 1.5 * vol` | s02 |
| **New R7** | `TrailingStop(0.04)` stmt template | all five |
| **New R7** | `rising(spread, n)` entry momentum gate | s03, s04, s05 |

## What we kept

- **Core theory:** every entry requires SMA/EMA micro-cross identity — level gate, OR-broaden, or SMA pair.
- **Fib windows only:** 5, 8, 13, 21, 34; MACD (13,34,8) + (8,21,5).
- **Never stack MACD/RSI on entry** — momentum filters live in cascade exit + onPosition only.

## R7 iteration thesis

1. **Drop don21 as sole FX gate** — hybrid `don13 \|\| close > ema21` (s02) or no-don (s01/s04) restores FX trade count.
2. **Tighter 4% hard stops** via `TrailingStop(0.04)` — crypto MDD halved vs equity 5% shell.
3. **Selectivity wins whipsaw** — `don21 && rising(spread,2)` on EMA 8/34 (s05) trades rarely but positively on BTC/SOL with 1.2% median MDD.
4. **SMA + rising spread** (s04) best cross-asset vs-BH (+0.659 mean d_sharpe) when FX participation matters.

## R7 lineup

| File | Strategy | Hypothesis |
|---|---|---|
| s01.ms | Ema813AnchorCascadeR7 | 8/13 micro + `close > ema34` trend filter — crypto uptrend only |
| s02.ms | Ema813HybridAtrR7 | 8/13 micro + `(don13 \|\| close > ema21)` + ATR lock — FX range recovery |
| s03.ms | Ema513RisingCascadeR7 | Fast 5/13 micro + `rising(spread,3)` — crypto burst capture |
| s04.ms | Sma813RisingFxR7 | SMA 8/13 + `rising(spread,2)` — smoothest FX participation |
| s05.ms | Ema834RiseDon21R7 | **Flagship:** 8/34 micro + don21 + rising spread — selective, low MDD |

## 3m self-test (10 symbols + WF score)

| File | Score | Mean Sharpe | Mean vs BH | Median MDD | WF |
|---|---:|---:|---:|---:|---:|
| R6 s02 (baseline) | −0.41 | −1.28 | +0.30 | 5.1% | −1.05 |
| **s05** | **0.420** | **+0.013** | **+0.870** | **1.2%** | **−0.001** |
| s04 | 0.209 | −0.198 | +0.659 | 2.6% | −0.479 |
| s02 | 0.020 | −0.440 | +0.417 | 3.6% | −0.676 |
| s01 | −0.013 | −0.501 | +0.356 | 3.7% | −0.629 |
| s03 | −0.186 | −0.694 | +0.163 | 2.3% | −0.965 |

**Primary bet:** **s05** — only lineup member with positive mean Sharpe and near-flat WF on crypto/FX causal fills.

## Spot checks (s05)

| Symbol | Sharpe | vs BH | Trades | MDD |
|---|---:|---:|---:|---:|
| BTCUSD | +0.546 | +2.13 | 4 | 1.4% |
| SOLUSD | +2.434 | +2.91 | 4 | 0.9% |
| ETHUSD | 0.000 | +1.71 | 0 | 0% |
| EURUSD | 0.000 | +3.26 | 0 | 0% |
| GBPUSD | 0.000 | +1.11 | 0 | 0% |

## Implementation notes

- **`TrailingStop` must be defined locally** in each file — not a global builtin.
- **CRLF line endings crash gene-runner** (`Cannot call null`); all `.ms` files use LF.
- Eval path: `examples/strategy-tournament/agents/agent-01/round-07/sXX.ms`
