# Agent 02 — Round 5 Plan (EMA Trend Architect)

## R4 recap

| Our rank | Strategy | Score | Mean Sharpe | vs BH | WF Sharpe |
|---:|---|---:|---:|---:|---:|
| **8** | s01 Ema813DonchVaultR4 | **1.038** | 1.420 | +0.035 | **1.847** |
| 14 | s03 Ema821DonchHardR4 | 1.015 | 1.395 | +0.011 | 1.801 |
| — | Field winner agent-06 s05 | **1.427** | 1.978 | +0.593 | 1.961 |

**Gap:** R4 s01 had elite WF but lagged agent-06 on 3m Sharpe (+0.558) and vs-BH (+0.558) because exits were Donchian-only.

## R5 thesis: EMA gate + stolen exit stack

Keep **e8 > e13** as the non-negotiable EMA identity. Graft agent-06's exit-only cascade (Donchian / MACD / RSI / EMA trail) and agent-03's `falling(m.hist, 3)` — never on entry.

### Key discovery (R5 eval)

| Variant | onBar exit | onPosition extras | Score | WF | Insight |
|---|---|---|---:|---:|---|
| s01 full cascade incl. `belowEma(13)` | cascadeExit(13) | EMA trail stack | 1.413 | 1.869 | Matches agent-06 minus EMA entry filter |
| **s03/s05 RSI vault** | rsiMacdExit (no belowEma) | s05 adds fall+trail | **1.469** | 1.849 | **Beats 1.427** — belowEma onBar is too eager |
| s02 fall crown | donch + RSI only | falling(hist,3) + trail | 1.444 | **2.161** | Best WF; MACD bear deferred to onPosition |
| s04 e8 > e21 | full cascade | same as s01 | 1.383 | 1.820 | Slower gate loses winner trades |

**Breakthrough:** EMA 8/13 gate + agent-06 s04 RSI vault (without onBar belowEma) scores **1.469** — **+0.042 vs field winner**, **+0.431 vs our R4 best**. The EMA gate filters ~2 bad entries per symbol while preserving cascade exit alpha.

## What we stole

| Pattern | Source | R5 application |
|---|---|---|
| `cascadeExit` / `rsiMacdExit` templates | agent-06 s05/s04 | s01–s05 exit side only |
| MACD(13,34,8) + RSI(13)>72 | agent-06 s04 | s03, s05 onBar exit |
| `falling(m.hist, 3)` onPosition | agent-03 s01 | s02, s05 delayed momentum exit |
| Layered onPosition (5% / 13-bar / profit lock / EMA trail) | agent-06 s05 | s01, s02, s04, s05 |
| Donchian 21/13 channel | agent-05/06 | All strategies |

## What we kept (EMA mandate)

- **Entry:** `e8 > e13 && donchianHigh(21)` (s01–s03, s05) or `e8 > e21` (s04)
- **Never:** pure Donchian entry; MACD/RSI on entry side
- **Never:** `e8 < e13` onBar exit (R4 proved harmful)
- **Fib windows:** 5, 8, 13, 21, 34 throughout MACD / EMA / Donchian / time stops

## Round 5 slate

| ID | Name | EMA engine | Exit stack | Score | WF |
|---|---|---|---|---:|---:|
| **s03** | Ema813RsiVaultR5 | e8 > e13 | rsiMacdExit onBar + minimal onPosition | **1.469** | 1.849 |
| **s05** | Ema813CrownFallR5 | e8 > e13 | s03 + falling(hist) + EMA trail onPosition | **1.469** | 1.849 |
| s02 | Ema813FallCrownR5 | e8 > e13 | donch+RSI onBar; fall+trail onPosition | 1.444 | **2.161** |
| s01 | Ema813CascadeCrownR5 | e8 > e13 | Full agent-06 cascade clone | 1.413 | 1.869 |
| s04 | Ema821CascadeR5 | e8 > e21 | Full cascade (medium gate) | 1.383 | 1.820 |

**Primary bet:** s03 — beats field winner while staying EMA-core.

**Flagship:** s05 — documents full stolen stack (RSI vault + falling hist + layered onPosition).

**WF hedge:** s02 — highest walk-forward (2.161) via deferred MACD exit.

## vs R4 / field

| Metric | R4 s01 | R5 s03 | agent-06 s05 | Delta (s03 vs field) |
|---|---:|---:|---:|---:|
| Score | 1.038 | **1.469** | 1.427 | **+0.042** |
| Mean Sharpe | 1.420 | **2.080** | 1.978 | +0.102 |
| vs buy-hold | +0.035 | **+0.696** | +0.593 | +0.103 |
| Median MDD | 0.081 | 0.069 | **0.034** | +0.035 |
| WF Sharpe | **1.847** | 1.849 | 1.961 | −0.112 |

Trade-off: s03 sacrifices agent-06's ultra-low MDD (0.034) for higher raw Sharpe and vs-BH. s01 retains the tight MDD profile at 1.413.

## Self-test command

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-02/round-05/s03.ms
python examples/strategy-tournament/agents/agent-02/round-05/eval_all.py
```
