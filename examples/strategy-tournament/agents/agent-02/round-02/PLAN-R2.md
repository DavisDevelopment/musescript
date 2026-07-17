# Agent 02 — Round 2 Plan (EMA Trend Architect)

## Round 1 recap

| Our rank | Strategy | Score | Mean Sharpe | vs BH | MDD |
|---:|---|---:|---:|---:|---:|
| **3** | s02 Ema834Ema21Gate | 0.827 | 1.13 | -0.26 | **4.3%** |
| 11 | s03 Ema1334Ema55Gate | 0.416 | 0.58 | -0.81 | 6.4% |
| 12 | s05 Ema813Ema21Trail | 0.352 | 0.49 | -0.89 | 8.0% |
| 13 | s04 Ema813Ex21Ema55 | 0.216 | 0.47 | -0.91 | 7.8% |
| 20 | s01 Ema821Sma55Gate | -0.472 | -0.16 | -1.54 | 0.0% |

**Winner:** agent-05 Donchian 21-high / 13-low + 13-bar time stop (score 1.002, +0.035 vs BH).

## What we stole (Donchian + podium peers)

| Pattern | Source | How we applied it |
|---|---|---|
| 13-bar Fib time stop | agent-05 s05 | Added to all R2 `onPosition` shells (was 21/34 in R1) |
| Asymmetric channel exits | agent-05 s05 | `low <= lowest(low, 13)` and `low <= lowest(low, 8)` as supplemental flat triggers |
| Breakout confirmation | agent-05 s05 | `high >= highest(high, 13/21)` gates EMA 8/34 entries (s02, s03) |
| Plain EMA 8/34 cross | agent-01 s05 | s04 — no trend gate, relies on 13-bar time + 5% equity shell |
| EMA 8/13 + EMA21 exit | agent-01 s02 | Dropped EMA55 macro filter (under-traded on 62-bar tape) |

## What we kept (EMA mandate)

- **Core engine:** EMA crossover entries (`crossover(fast, slow)`) — never replaced with pure Donchian entry
- **Regime filters:** EMA 13/21 trend gates (dropped SMA/EMA 55 — caused R1 s01 zero-trade failures)
- **Risk shells:** 5% equity hard stop + Fib time stops via `onPosition`
- **Anchor pair:** EMA 8/34 (R1 podium engine)

## Round 2 slate

| ID | Name | Engine | Filter / steal | Risk shell | 10-sym mean Sharpe |
|---|---|---|---|---|---:|
| s01 | Ema834Ema21GateR2 | EMA 8/34 | EMA 21 gate (podium keeper) | 13-bar time + 5% equity | 1.13 |
| s02 | Ema834Break13Gate | EMA 8/34 | EMA 21 + Donchian 13-high break | 13-bar time + 5% equity | **1.25** |
| s03 | Ema834Break21Gate | EMA 8/34 | EMA 21 + Donchian 21-high break | 13-bar time + 5% equity | 1.19 |
| s04 | Ema834Plain13 | EMA 8/34 | none (agent-01 plain cross) | 13-bar time + 5% equity | 1.18 |
| s05 | Ema821Ema13Gate | EMA 8/21 | EMA 13 micro-gate + Donch 8-low exit | 13-bar time + 5% equity | 1.01 |

**Best 10-symbol self-test:** s02 (mean Sharpe 1.25, vs R1 s02 1.13 — +10% lift from breakout filter skipping AMZN whipsaw).

## Dropped from R1

- SMA 55 / EMA 55 trend gates (too slow → zero trades on short tape)
- 21/34-bar time stops (replaced by winner's 13-bar stop)
- EMA 13/34 and EMA 8/13 standalone variants (underperformed on cross-symbol eval)

## Iteration notes

Breakout filters (s02, s03) are the main R2 innovation: they preserve EMA cross entries but require price to confirm momentum via `highest(high, N)` — stealing Donchian's edge without abandoning the EMA architect mandate. s04 provides a simpler cross-symbol hedge (no gate, higher MDD tolerance). s01 is the conservative podium baseline with only the 13-bar time stop added.
