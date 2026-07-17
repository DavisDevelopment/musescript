# Agent 01 — Round 6 Plan (FINAL)

## R5 recap

| Strategy | Score | vs BH | Key issue |
|---|---:|---:|---|
| s01 Ema834CascadeCrownR5 | **1.404** | +0.599 | Strong Sharpe but MDD 6.9%, exit-only don13 onBar |
| agent-05 s04 (champion) | **1.549** | +0.702 | Full cascade onBar + m8 falling + RSI 75 |

**Gap diagnosis:** R5 stole CascadeCrown `onPosition` but kept minimal `onBar` exit (don13 only). Champion lifted score via **onBar cascade** (don13 ‖ MACD bear ‖ RSI>75 ‖ <ema13) + **falling(m8.hist,3)**. MDD dropped 6.9% → 2.9%.

## What we stole (R6)

| Source | Pattern | Applied in |
|---|---|---|
| **agent-05 / s04** | Full `cascadeExit(13)` onBar + RSI 75 + falling(m8,3) onPosition | all five |
| **agent-05 / s04** | MACD(8,21,5) fast-fade exit (not m1348) | all five |
| **agent-05 / s05** | crossunder(m8.macd, m8.signal) dual trim | s05 |
| **Our R5 s01** | EMA 8/34 level gate micro-cross | s01 |
| **Our BRIEF** | EMA 8/13 faster micro pair | s02, s03 |
| **Our R1** | SMA 8/13 cross identity | s04 |
| **Probe p13** | `(fast > slow \|\| close > fast)` entry OR-broaden | s01, s02 |

## What we kept

- **Core theory:** every entry requires SMA/EMA micro-cross identity — level gate (`fast > slow`), dual micro (`fast > micro`), or SMA pair.
- **Donchian 21 confirm** on entry — additive burst filter, not the thesis.
- **Fib windows only:** 5, 8, 13, 21, 34, 55; MACD (13,34,8) + (8,21,5).
- **Never stack MACD/RSI on entry** — all momentum filters live in cascade exit + onPosition.

## R6 iteration thesis

1. **Steal champion exit wholesale, keep micro-cross entry** — onBar cascade + m8 falling closes the 0.145 score gap from R5.
2. **OR-broaden entry without abandoning identity** — `(fast > slow || close > fast)` captures champion's `close > e8` recovery bars while preserving EMA 8/13 or 8/34 cross geometry; lifts WF 2.30 → 2.34.
3. **Beat 1.549** — s01/s02 hit **1.555** on full 10-symbol 3m + WF eval.
4. **Diversify entry geometry** — 8/34 OR, 8/13 OR, 8/5 dual, SMA 8/13, EMA 5/13 swing.

## R6 lineup

| File | Strategy | Hypothesis |
|---|---|---|
| s01.ms | Ema834OrCloseCascadeR6 | 8/34 micro OR-broaden + champion cascade — ties s02 score |
| s02.ms | Ema813OrCloseCascadeR6 | **Flagship:** 8/13 micro OR-broaden + full cascade — **beats champion** |
| s03.ms | Ema85DualCascadeR6 | Dual micro 8/5 + close>8 confirm — ties champion, tighter identity |
| s04.ms | Sma813Cascade75R6 | SMA 8/13 level + cascade + crossunder exit — SMA identity diversifier |
| s05.ms | Ema513CascadeR6 | Faster EMA 5/13 swing + m8 crossunder trim — higher trade count |

## 3m self-test (10 symbols + WF score)

| File | Score | Mean Sharpe | Mean vs BH | Median MDD | WF |
|---|---:|---:|---:|---:|---:|
| R5 s01 | 1.404 | 1.983 | +0.599 | 6.9% | 1.833 |
| champion s04 | 1.549 | 2.086 | +0.702 | 2.9% | 2.300 |
| **s01** | **1.555** | **2.086** | **+0.702** | **2.9%** | **2.338** |
| **s02** | **1.555** | **2.086** | **+0.702** | **2.9%** | **2.338** |
| s03 | 1.549 | 2.086 | +0.702 | 2.9% | 2.300 |
| s04 | 1.142 | 1.653 | +0.269 | 1.9% | 1.451 |
| s05 | 1.513 | 2.062 | +0.678 | 2.9% | 2.164 |

**Target:** beat 1.549. **Achieved:** s01/s02 at **1.555** (+0.006). Primary bet: **s02** (cleanest 8/13 micro-cross mandate).

## SPY spot check (s02)

- Sharpe **3.31** | vs BH **+1.02** | MDD **1.1%** | 13 trades
