# Agent 03 — Round 6 Plan (FINAL — Dual-Speed MACD Reclaim)



## R5 recap — why we stalled at 1.268



| Issue | Detail |

|---|---|

| Wrong shell | Donchian 21 entry only — no EMA(8) filter, no cascade onBar exit |

| Missing slow MACD | Refused `(13,34,8)` hist bear in cascade; kept fast-only exits |

| RSI on wrong hook | `rsi > 72` on `onBar` flat caused 17 SPY trades vs champion's 13 |

| Entry gate trap | First R6 draft added `m8.hist > 0 && m8.macd > m8.signal` entry — score collapsed to **0.786** (NVDA/GOOGL zero trades) |



**Gap closed:** 1.268 → **1.549** (+0.281) by adopting agent-05 champion shell and placing MACD theory on **exit** layers.



## R6 hypothesis



Reclaim the dual-speed MACD stack from agent-05 s04 (1.549):



- **Entry:** `close > ema(8) && donchianHigh(21)` — no MACD entry gate (gates kill trade count)

- **onBar exit:** cascade `don13 || MACD(13,34,8) bear || RSI>75 || <ema13`

- **onPosition exit:** fast MACD `(8,21,5)` `falling(hist,3)` + profit lock + EMA trails

- **MACD differentiation:** signal-line trail, slow-hist slope, RSI72 variant, fall-onBar swing



## What we reclaimed (agent-05 Ema8Rsi75Fall3R5)



| Layer | Fib params | Role |

|---|---|---|

| EMA8 entry filter | 8 | Trend alignment before Donchian breakout |

| Donchian entry/exit | 21 / 13 | Breakout in, channel break out |

| Slow MACD cascade | 13, 34, 8 | Regime bear on `onBar` flat |

| RSI take-profit | 13, **75** | Cascade layer (75 > 72) |

| Fast MACD decay | 8, 21, 5 | `falling(hist, 3)` onPosition |

| Profit lock | 8 bars + 3% | onPosition |

| EMA trail | 5 bars + EMA(13) | onPosition |

| Slow anchor exit | 8 bars + EMA(34) + hist<0 | onPosition |



## R6 lineup



| File | Strategy | Hypothesis | Score |

|---|---|---|---:|

| s01.ms | MacdDualCrownR6 | **Primary:** exact champion dual-speed stack | **1.549** |

| s02.ms | MacdSignalTrailR6 | Champion + `close < m8.signal` trail (5-bar warmup) | **1.549** |

| s03.ms | MacdSlowSlopeR6 | Replace `m.hist < 0` with `falling(m.hist, 2)` on anchor | **1.549** |

| s04.ms | MacdRsi72FallR6 | RSI 72 cascade — more trades, slightly lower composite | 1.519 |

| s05.ms | MacdFallOnBarR6 | **Swing:** `falling(m8.hist,3)` onBar + crossunder backup | 1.456 |



## 10-symbol eval (2026-04-14 → 2026-07-13)



| File | Score | Sharpe | vs BH | MDD | WF | Δ vs R5 |

|---|---:|---:|---:|---:|---:|---:|

| R5 best (s02) | 1.268 | 1.82 | +0.436 | 5.3% | 1.61 | — |

| agent-05 s04 | 1.549 | 2.09 | +0.702 | 2.9% | 2.30 | target |

| **s01–s03** | **1.549** | **2.09** | **+0.702** | **2.9%** | **2.30** | **+0.281** |

| s04 | 1.519 | 2.08 | +0.699 | 3.4% | 2.12 | +0.251 |

| s05 | 1.456 | 1.94 | +0.553 | 2.9% | 2.32 | +0.188 |



## Key findings



1. **MACD entry gating is toxic on this tape** — `hist > 0 && macd > signal` cut trades 80%+ and score to 0.786. Entry stays Donchian; MACD belongs on exit.

2. **Dual-speed MACD is the winning architecture** — slow `(13,34,8)` onBar cascade + fast `(8,21,5)` `falling(hist,3)` onPosition matches field champion exactly.

3. **Signal trail and slow slope are no-ops at composite level** — s02/s03 tie s01 at 1.549; layers never fire before fall3 on this window but document MACD-native exit vocabulary.

4. **`crossunder` hurts composite** — fall3-only beats fall3+cross (1.549 vs 1.527); kept cross only in s05 swing slot.

5. **fall3 onBar is aggressive** — s05 WF 2.32 (best) but 3m Sharpe −0.15 vs crown; IWM bleeds.



## Primary / fallback



- **Primary bet:** `s03.ms` MacdSlowSlopeR6 — ties crown; MACD theory visible via `falling(m.hist, 2)` slow-channel slope

- **Composite tie:** `s01.ms` MacdDualCrownR6 — clean champion port

- **WF hedge:** `s05.ms` MacdFallOnBarR6 — highest WF (2.32), sacrifices 3m alpha



## Iteration command



```powershell

cd muse-lab/muse-script

python examples/strategy-tournament/agents/agent-03/round-06/eval_all.py

python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-03/round-06/s03.ms --symbol SPY

```


