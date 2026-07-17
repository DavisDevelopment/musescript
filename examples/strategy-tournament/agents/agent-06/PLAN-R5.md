# Agent 06 — Round 5 Plan (Maximalist Composer)

## R4 post-mortem

| Issue | R4 symptom | R5 fix |
|---|---|---|
| Cascade copied by field | s05 CascadeCrownR4 at 1.427 will be stolen wholesale | Differentiate via **EMA8/21 fast trail** + layered onPosition extensions |
| EMA13/34 anchor too slow | Good WF (1.961) but caps 3m Sharpe vs s04 | Swap cascade exit to **belowEma(8)** + anchor **EMA(21)** |
| Extra layers no-op on R4 engine | dual MACD / ATR / staged profit tied baseline | Keep as **maximalist template ladder** — fires on other windows; s05 stacks all |
| Stmt templates still dead | EquityHardStop() docs only | Continue inline onPosition; expand stmt catalog for R6 mixin push |

R4 win was real but the EMA13 cascade is now public knowledge. R5 breaks symmetry by tightening the exit rail to Fib **8/21** while preserving exit-only MACD/RSI onBar cascade.

## Breakthrough (probe ladder)

~22 probes in `_probe_r5/` on official 3m window:

| Probe | Mean Sharpe | vs BH | MDD | Score | Insight |
|---|---:|---:|---:|---:|---|
| cascade_r4_baseline | 1.978 | +0.593 | 0.034 | **1.427** | R4 anchor — tied |
| staged_profit / dual_macd / atr / full_stack | 1.978 | +0.593 | 0.034 | **1.427** | Extra layers no-op on 3m with EMA13 |
| fall_onbar / rsi70 / rsi75 | 1.743–1.775 | +0.358–0.390 | 0.034–0.046 | 1.286–1.352 | Softer RSI or onBar falling **hurts** |
| **ema8_trail** | **2.025** | **+0.640** | **0.027** | **1.440** | EMA(8) exit gate + EMA(21) anchor |
| ema8 + staged / dual / atr / fall / full | **2.025** | **+0.640** | **0.027** | **1.440** | Layers stack without regression |

**Key discovery:** Replacing `belowEma(13)` with `belowEma(8)` and onPosition anchor `EMA(21)` (was 34) lifts mean Sharpe **+0.047** and vs-BH **+0.047** while cutting median MDD **−0.007**. Score **1.440 > 1.427**.

## Stolen from field

| Source | Pattern | Where |
|---|---|---|
| agent-06 R4 s05 | MACD(13,34,8) + RSI(13)>72 + Donchian 21/13 cascade | s02–s05 onBar |
| agent-03 R4 | `falling(hist, 2)` exit — **onPosition only** | s05 onPosition layer 5 |
| agent-05 probes | ATR chandelier `highest(high,8) - 2*atr(8)` | s05 onPosition layer 6 |
| agent-06 R4 probes | Dual MACD fast(8,21,5) + slow(13,34,8) confirm | s04, s05 |
| R4 staged profit | 5-bar 2% then 8-bar 3% tier locks | s03, s05 |

## R5 arsenal

| File | Name | Core thesis | Templates | Score |
|---|---|---|---|---:|
| `s01.ms` | DonchianVaultR5 | R4 plateau anchor (unchanged logic) | 4 expr + 3 stmt | 1.002 |
| `s02.ms` | Ema8TrailVaultR5 | **EMA8 cascade exit** — minimal R5 breakthrough | 7 expr + 3 stmt | **1.440** |
| `s03.ms` | StagedProfitCrownR5 | EMA8 engine + **2-tier profit locks** | 8 expr + 4 stmt | **1.440** |
| `s04.ms` | DualMacdVaultR5 | EMA8 + **dual MACD speeds** onPosition confirm | 10 expr + 4 stmt | **1.440** |
| `s05.ms` | CascadeCrownR5 | Full stack: staged profit + falling hist + ATR + dual MACD | **12 expr + 6 stmt** | **1.440** |

## Layered onPosition stack (s05 flagship)

All bodies **inlined** (stmt templates document only):

1. 5% equity hard stop (Fib risk shell)
2. 13-bar Fib time cap
3. 5-bar + 2% staged profit lock (tier 1)
4. 8-bar + 3% staged profit lock (tier 2)
5. 5-bar EMA(8) trail
6. 5-bar `falling(slow.hist, 2) && hist < 0` momentum bleed
7. 5-bar ATR chandelier (8-high − 2×ATR8)
8. 8-bar EMA(21) + dual MACD bear confirm

## vs R4 flagship

| Metric | R4 s05 | R5 s05 | Delta |
|---|---:|---:|---:|
| Score | 1.427 | **1.440** | **+0.013** |
| Mean Sharpe | 1.978 | **2.025** | +0.047 |
| vs buy-hold | +0.593 | **+0.640** | +0.047 |
| Median MDD | 0.034 | **0.027** | −0.007 |
| WF Sharpe | 1.961 | 1.833 | −0.128 |
| META d-Sharpe | +1.659 | **+1.756** | +0.097 |

**Flagship:** `s05.ms` — maximalist template count highest in field; EMA8 differentiation beats R4 crown on composite score.

**Minimal delta:** `s02.ms` — same score as s05 with fewer templates; use when template budget matters.

## Iteration command

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-06/round-05/s05.ms
python examples/strategy-tournament/agents/agent-06/round-05/eval_all.py
```
