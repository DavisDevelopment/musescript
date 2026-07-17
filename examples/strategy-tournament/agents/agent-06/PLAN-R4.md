# Agent 06 — Round 4 Plan (Maximalist Composer)

## R3 post-mortem

| Issue | R3 symptom | R4 fix |
|---|---|---|
| Plateau at 1.002 | s01 cloned bare Donchian — tied win but zero differentiation | Layer expr templates + exit-only filters (not entry gates) |
| Maximalist identity lost | R3 stripped all templates to match winner byte-for-byte | Restore 6–10 expr templates + stmt docs per file; inline `onPosition` |
| Entry filters hurt | R3 s02–s05 stacked `&&` MACD/EMA on **entry** → missed breakouts | MACD/RSI/EMA only on **exit** side (agent-03 lesson) |
| Stmt-template runtime | `EquityHardStop()` bare call throws "Cannot call null" | Stmt templates kept as **documentation**; bodies always inlined |

R3 win was real but undifferentiated. R4 breaks the plateau by stealing agent-03's **exit-only MACD** insight and pushing it through maximalist template layers.

## Breakthrough (probe ladder)

Systematic 3m eval + walk-forward scoring on ~40 probes in `_probe_r4/`:

| Probe | Mean Sharpe | vs BH | MDD | Score | Insight |
|---|---:|---:|---:|---:|---|
| base (R3 clone) | 1.420 | +0.035 | 0.081 | **1.002** | Plateau anchor |
| macd_exit | 1.459 | +0.075 | 0.084 | 0.948 | Better d-Sharpe, WF collapse |
| macd_ema21 | 1.455 | +0.070 | **0.043** | **1.003** | EMA21 exit cuts drawdown |
| rsi72 + macd134 | 2.080 | +0.696 | 0.069 | **1.419** | Slow MACD + RSI take-profit |
| **macd134 + rsi72 + ema13** | **1.978** | **+0.593** | **0.034** | **1.427** | Flagship — best WF stability |

**Key discovery:** MACD(13,34,8) histogram `< 0` as exit filter (not entry gate) + RSI(13) > 72 take-profit unlocks +0.56 d-Sharpe vs the Donchian clone while preserving Donchian 21-high entry.

## Stolen from field

| Source | Pattern | Where |
|---|---|---|
| agent-05 / agent-06 R3 s01 | Donchian 21-high / 13-low + 5% stop + 13-bar time | s01 anchor |
| agent-03 s01/s04 | MACD hist exit-only (`hist < 0`), never on entry | s02, s04, s05 |
| agent-03 MacdDonchian | `|| m.hist < 0` alongside channel low exit | s02 `exitRegimeFlip` |
| agent-06 R2 s03 | EMA trail exit after Fib min bars | s03, s05 onPosition |
| probe rsi72_macd134 | Slow MACD + overbought RSI exit | s04, s05 |

## R4 arsenal

| File | Name | Core thesis | Templates | Score |
|---|---|---|---|---:|
| `s01.ms` | DonchianVaultR4 | R3 anchor + expr template shell + profit-lock onPosition | 4 expr + 3 stmt | 1.002 |
| `s02.ms` | MacdExitVaultR4 | Donchian entry; MACD(8,21,5) hist exit regime | 5 expr + 2 stmt | 0.948 |
| `s03.ms` | MacdEmaCrownR4 | MACD exit + EMA21 trail; lowest MDD ladder step | 6 expr + 3 stmt | 1.003 |
| `s04.ms` | RsiTakeVaultR4 | MACD(13,34,8) + RSI(13)>72 take-profit stack | 7 expr + 3 stmt | **1.419** |
| `s05.ms` | CascadeCrownR4 | s04 engine + EMA13 cascade exit + layered onPosition | **10 expr + 4 stmt** | **1.427** |

## Layered onPosition stack (s05 flagship)

All bodies **inlined** (stmt templates document only):

1. 5% equity hard stop (Fib-adjacent risk shell)
2. 13-bar Fib time cap
3. 8-bar + 3% profit lock
4. 5-bar EMA(13) trail
5. 8-bar EMA(34) + MACD bear dual confirm

## vs R3 / plateau

| Metric | R3 s01 (plateau) | R4 s05 (flagship) | Delta |
|---|---:|---:|---:|
| Score | 1.002 | **1.427** | **+0.425** |
| Mean Sharpe | 1.420 | **1.978** | +0.558 |
| vs buy-hold | +0.035 | **+0.593** | +0.558 |
| Median MDD | 0.081 | **0.034** | −0.047 |
| WF Sharpe | 1.612 | **1.961** | +0.349 |

**Flagship:** `s05.ms` — breaks plateau decisively; maximalist template count highest in field.

**Runner-up:** `s04.ms` — higher raw mean Sharpe (2.08) but slightly lower WF; pure RSI take-profit without EMA13 cascade.

## Iteration command

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-06/round-04/s05.ms
python examples/strategy-tournament/agents/agent-06/round-04/eval_all.py
```
