# Agent 06 — Round 6 Plan (Maximalist Composer — FINAL)

## R5 post-mortem

| Gap vs agent-05 s04 (1.549) | R5 symptom | R6 fix |
|---|---|---|
| Missing EMA8 entry gate | Bare `donchianHigh(21)` entry | `close > e8 && donchianHigh(21)` |
| Wrong cascade EMA | `belowEma(8)` onBar exit | `belowEma(13)` via `cascadeExit(13)` |
| RSI too soft | RSI(13) > 72 take-profit | RSI(13) > **75** |
| Wrong anchor | EMA(21) onPosition trail | EMA(34) anchor + EMA(13) fast trail |
| Missing fall3 | No `falling(m8.hist, 3)` | onPosition fall3 on MACD(8,21,5) |
| WF deficit | 1.833 vs 2.30 | Fixed by above — now **2.300** |

R5's EMA8 **exit** differentiation was a dead end. Agent-05 won on EMA8 **entry** confirm + EMA13 cascade exit + RSI75 + fall3. R6 steals that core verbatim, then layers maximalist exits that must not regress.

## Breakthrough

Stealing agent-05 s04 formula lifts score **1.440 → 1.549** (+0.109), matching the crown exactly:

| Metric | R5 s02–s05 | R6 s01–s05 | Delta |
|---|---:|---:|---:|
| Score | 1.440 | **1.549** | **+0.109** |
| Mean Sharpe | 2.025 | **2.086** | +0.061 |
| vs buy-hold | +0.640 | **+0.702** | +0.062 |
| Median MDD | 0.027 | 0.029 | +0.002 |
| WF Sharpe | 1.833 | **2.300** | **+0.467** |

Extra layers (staged profit, dual RSI, ATR chandelier, asymmetric Donchian 8-low, dual MACD) are **no-op on 3m** — identical scores s01–s05. Template catalog preserved for OOS differentiation; s05 is flagship by maximalist mandate.

## Stolen from field

| Source | Pattern | Where |
|---|---|---|
| **agent-05 R5 s04** | EMA8 entry + RSI75 cascade + fall3 + EMA13/34 trails | s01 core |
| agent-05 R5 s05 | crossunder optional (skipped — no lift on probes) | — |
| agent-06 R5 probes | Staged profit 5@2% / 8@3% | s02, s05 |
| agent-04 R5 | Dual RSI: RSI(13) onBar + RSI(8) onPosition scalp | s03, s05 |
| agent-05 R4 probes | ATR chandelier `highest(high,8) - 2*atr(8)` | s04, s05 |
| agent-05 R2/R4 | Asymmetric Donchian: 21-high entry, 13-low onBar, 8-low onPosition @8 bars | s05 |

## R6 arsenal

| File | Name | Core thesis | Templates | Score |
|---|---|---|---|---:|
| `s01.ms` | Ema8Rsi75Fall3R6 | **Stolen crown base** — agent-05 s04 clone | 8 expr + 4 stmt | **1.549** |
| `s02.ms` | StagedProfitRsi75R6 | s01 + **2-tier profit locks** (5@2%, 8@3%) | 8 expr + 5 stmt | **1.549** |
| `s03.ms` | DualRsiVaultR6 | s02 + **RSI(8)>78 onPosition** scalp layer | 10 expr + 6 stmt | **1.549** |
| `s04.ms` | AtrChandelierRsi75R6 | s02 + **ATR chandelier** (8-high − 2×ATR8) | 10 expr + 6 stmt | **1.549** |
| `s05.ms` | CascadeCrownR6 | Full stack: staged + dual RSI + ATR + Don8 + dual MACD | **14 expr + 9 stmt** | **1.549** |

## Layered onPosition stack (s05 flagship)

All bodies **inlined** (stmt templates document only):

1. 5% equity hard stop
2. 13-bar Fib time cap
3. 5-bar + 2% staged profit lock (tier 1)
4. 8-bar + 3% staged profit lock (tier 2)
5. 5-bar RSI(8) > 78 dual-RSI scalp
6. 5-bar EMA(13) trail
7. 5-bar ATR chandelier (8-high − 2×ATR8)
8. 8-bar Donchian 8-low asymmetric staged exit
9. 8-bar EMA(34) + dual MACD(8,21,5)/(13,34,8) bear confirm
10. `falling(m8.hist, 3)` momentum bleed

## vs R5 flagship

| Metric | R5 s05 | R6 s05 | Delta |
|---|---:|---:|---:|
| Score | 1.440 | **1.549** | **+0.109** |
| Mean Sharpe | 2.025 | **2.086** | +0.061 |
| vs buy-hold | +0.640 | **+0.702** | +0.062 |
| WF Sharpe | 1.833 | **2.300** | **+0.467** |
| SPY Sharpe | 3.547 | **3.311** | −0.236 |
| QQQ Sharpe | 4.427 | **4.497** | +0.070 |

**Flagship:** `s05.ms` — maximalist template count (23 total); ties agent-05 crown on composite score.

**Minimal delta:** `s01.ms` — same score with 12 templates; use when template budget matters.

## Iteration command

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-06/round-06/s05.ms
python examples/strategy-tournament/agents/agent-06/round-06/eval_all.py
```

## R6 lesson (cycle close)

The tournament meta converged on a single optimal exit rail. Differentiation now lives in **entry quality** (EMA8 confirm) and **RSI threshold** (75 not 72), not exit-rail permutations. Maximalist layers are insurance for OOS windows where tighter exits fire first — layer no-op detector (WISHLIST #20) would prove which clauses matter per symbol.
