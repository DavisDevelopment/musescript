# Agent 02 — Round 7 Plan (Crypto + FX)

## Domain shift

Equity EMA trend edges do **not** transfer. Causal next-open on Apr–Jul 2026 crypto/FX is mostly bear/range — buy-and-hold Sharpe is negative on 8/10 symbols. Score comes from **avoiding losses** (cash) and selective long trend pockets (USDCAD, USDJPY, ADA).

## Probe findings

| Probe | Entry | Score | Notes |
|---|---:|---|
| crossover-only + SMA(55) | event cross | ~0.16 | Almost no trades — gate too slow |
| dual SMA(55) && SMA(89) | level | ~0.41 | Zero trades entire window |
| bare EMA 8/34 OR-broaden | no gate | −0.11 | Too many whipsaw losses |
| **EMA 8/34 OR + SMA(21)** | level + light gate | **0.30–0.38** | Sweet spot |
| EMA 8/89 slow + close > e89 | slow trend | 0.10 | Fewer events, mixed |
| EMA 13/34 + rising(spread) | momentum confirm | 0.22 | Helps ADA/BTC, hurts SOL |
| OR trend gate sma21 \|\| ema55 | broad gate | 0.23 | More crypto trades, worse FX |

**Key lesson:** Slower SMA trend gates (55, 89) block nearly all entries on this window. Use **SMA(21)** or **EMA(55)** single gates. Entry must be **level OR-broaden** `(fast > slow || close > fast)`, not crossover events alone.

## What we kept (EMA Trend Architect mandate)

- EMA pairs from BRIEF: **8/34**, **8/89**, **13/34**, plus **8/21** mid-speed trigger
- SMA trend filters at Fib windows **21**, **55**, **89** — but only as **single** gates or OR-combined
- `onPosition` time stops + `TrailingStop` stmt template + `falling(..., minBars)` slope exits
- Fib windows only: 5, 8, 13, 21, 34, 55, 89

## What we stole

| Source | Pattern | Applied in |
|---|---|---|
| agent-01 R6/R7 | `emaTrendEntry` OR-broaden `(fast > slow \|\| close > fast)` | all five |
| agent-01 R7 | `TrailingStop(pct)` stmt template (must inline definition) | all five |
| Cycle-2 gifts | `falling(x, n, minBars)` gated by `bars_in_trade` | s01–s05 |
| agent-01 R7 | `position() == 0` entry latch | s05 |

## R7 lineup

| File | Strategy | Hypothesis |
|---|---|---|
| s01.ms | Ema834Gate21R7 | **Flagship:** classic 8/34 OR-broaden + SMA(21) gate — best score |
| s02.ms | Ema889SlowTrendR7 | Slow 8/89 pair + close > e89 anchor — diversifier for sustained trends |
| s03.ms | Ema1334RisingBurstR7 | 13/34 + rising spread + EMA(55) gate — mid-speed momentum burst |
| s04.ms | Ema821Gate21R7 | Faster 8/21 trigger + SMA(21) — more FX events, near-flagship score |
| s05.ms | Ema834CrownFlagshipR7 | s01 core + EMA(13) trail + position latch + layered exits |

## 3m self-test (10 symbols + WF score, next-open)

| File | Score | Mean Sharpe | vs BH | Median MDD | WF |
|---|---:|---:|---:|---:|---:|
| **s01** | **0.379** | 0.032 | +0.889 | 2.3% | −0.339 |
| s04 | 0.354 | 0.008 | +0.865 | 2.3% | −0.409 |
| s05 | 0.295 | −0.090 | +0.767 | 2.5% | −0.370 |
| s03 | 0.216 | −0.247 | +0.609 | 2.3% | −0.216 |
| s02 | 0.100 | −0.355 | +0.502 | 4.6% | −0.495 |

**Target:** positive score on crypto+FX causal window. **Achieved:** s01 at **0.379**. Primary bet: **s01**.

## BTC / EUR spot check (s01)

```powershell
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-02/round-07/s01.ms --symbol BTCUSD
python examples/strategy-tournament/harness/crypto_fx_lab.py --eval agents/agent-02/round-07/s01.ms --symbol EURUSD
```

- BTC: 5 trades, Sharpe +0.05, +0.05% return; vs BH +1.63 d_sharpe
- EUR: 2 trades, small loss; vs BH +1.10 d_sharpe

## R7 thesis

Slower EMA trend theory survives crypto+FX only when **OR-broadened level entries** replace crossover events and trend gates use **fast Fib SMA(21)** instead of SMA(55/89). The edge is defensive: sit out the whipsaw, clip FX trends on USDCAD/USDJPY.
