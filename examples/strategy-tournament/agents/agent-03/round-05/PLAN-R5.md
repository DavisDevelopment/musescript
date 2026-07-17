# Agent 03 — Round 5 Plan (MACD Momentum + Cascade Steal)

## R4 recap

| Rank | Strategy | Score | Sharpe | vs BH | MDD | WF | Key |
|---:|---|---:|---:|---:|---:|---:|---|
| **#3** | s01 MacdFall3CrossExit | **1.267** | 1.89 | **+0.500** | 5.7% | 1.33 | `falling(hist,3) \|\| crossunder` |
| — | agent-06 s05 CascadeCrown | **1.427** | 1.98 | +0.593 | 3.4% | 1.96 | RSI TP + EMA trail + profit lock |

**Gap to close:** 0.160 composite points. R4 proved `falling(m.hist, 3)` beats binary `hist < 0`; agent-06 proved layered exit-only filters (RSI, EMA, profit lock) lift vs-BH and WF without touching entry.

## R5 hypothesis

Keep MACD `(8, 21, 5)` histogram slope as **theory layer**; graft agent-06 CascadeCrown **exit stack** (profit lock, EMA trail, RSI take-profit) without adopting their slow MACD `(13, 34, 8)`.

## What we stole (agent-06 CascadeCrown)

| Pattern | Fib params | Applied in |
|---|---|---|
| Profit lock | 8 bars + 3% equity | s01, s02, s03, s05 |
| EMA trail | 5 bars + EMA(13) or EMA(8) | s01, s03, s05 |
| RSI take-profit | RSI(13) > 72 on `onBar` flat | s02, s03, s05 |
| Cascade onBar exit | `\|\|` donchian / RSI / EMA | s03 |
| Risk shell | 5% stop + T13 | all five |

## What we kept (MACD regime theory)

- **Core signal:** `falling(m.hist, N)` momentum deceleration + `crossunder(m.macd, m.signal)` backup — never `hist < 0` on `onBar`.
- **Entry:** Donchian 21-high breakout, no MACD entry gate.
- **MACD params:** `(8, 21, 5)` — faster than agent-06's `(13, 34, 8)`.
- **Fib windows only:** 2, 3, 5, 8, 13, 21.

## R5 lineup

| File | Strategy | Hypothesis |
|---|---|---|
| s01.ms | MacdFall3Crown | **3m alpha bet:** R4 s01 + profit lock + EMA13 trail in onPosition |
| s02.ms | MacdFall3RsiVault | **Composite bet:** R4 s01 + RSI(13)>72 onBar flat + profit lock |
| s03.ms | MacdCascadeFall3 | Full cascade steal — RSI/EMA onBar + delayed fall3 in onPosition |
| s04.ms | MacdFall3ProfitAnchor | WF-safe: 8-bar warmup before fall3/cross exits + profit lock |
| s05.ms | MacdFall2Cascade | Aggressive fall2 + RSI + EMA8 trail + profit lock |

## 10-symbol eval (2026-04-14 → 2026-07-13)

| File | Score | Sharpe | vs BH | MDD | WF | Δ vs R4 s01 |
|---|---:|---:|---:|---:|---:|---:|
| R4 s01 | 1.267 | 1.89 | +0.500 | 5.7% | 1.33 | — |
| agent-06 s05 | 1.427 | 1.98 | +0.593 | 3.4% | 1.96 | target |
| **s02** | **1.268** | 1.82 | +0.436 | 5.3% | **1.61** | **+0.001** |
| s01 | 1.267 | **1.89** | **+0.500** | 5.7% | 1.33 | 0.000 |
| s05 | 1.238 | 1.84 | +0.454 | 6.4% | 1.35 | −0.029 |
| s03 | 1.226 | 1.67 | +0.287 | **3.4%** | **1.95** | −0.041 |
| s04 | 1.002 | 1.42 | +0.035 | 8.1% | 1.61 | −0.265 |

## Findings

1. **RSI take-profit (s02) is the only layer that moved composite** — WF jumped 1.33 → 1.61 (+0.28) at cost of −0.06 mean Sharpe; net +0.001 score.
2. **EMA trail + profit lock alone (s01) are no-ops** on this tape — identical score to R4 s01; layers never fire before `falling(hist,3)`.
3. **Full cascade (s03) cuts MDD to 3.4%** (matches agent-06 winner) and WF hits 1.95, but 3m Sharpe drops −0.21 — over-trading from RSI onBar flat (17 SPY trades vs 5).
4. **Delayed warmup (s04) collapses 3m alpha** — ties plateau at 1.002; same R4 lesson as s04 MacdDelayedHistExit.
5. **Gap to 1.427 remains ~0.16** — agent-06's slow MACD `(13,34,8)` hist exit onBar may be the missing piece we refused to adopt.

## Primary / fallback

- **Primary bet:** `s02.ms` MacdFall3RsiVault — best composite (1.268), best WF among fall3 variants
- **3m alpha fallback:** `s01.ms` MacdFall3Crown — ties R4 on score but preserves +0.50 vs-BH
- **WF / MDD hedge:** `s03.ms` MacdCascadeFall3 — lowest MDD (3.4%), WF 1.95

## Iteration command

```powershell
cd muse-lab/muse-script
python examples/strategy-tournament/agents/agent-03/round-05/eval_all.py
python examples/strategy-tournament/harness/tournament_lab.py --eval examples/strategy-tournament/agents/agent-03/round-05/s02.ms --symbol SPY
```
