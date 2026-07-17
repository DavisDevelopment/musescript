# Agent 06 — Round 7 Plan (Maximalist Composer — Crypto + FX)

## Domain reset

| | Equity R6 | Crypto+FX R7 |
|---|---:|---:|
| Execution | same-close | **next-open only** |
| Eval window | 2026-04-14 → 2026-07-13 | same |
| Crown score | **1.549** | **0.171** (s02–s05) |
| Mean Sharpe | 2.086 | −0.060 |
| vs buy-hold | +0.702 | **+0.797** |
| WF Sharpe | 2.300 | **−1.318** |

Equity-cycle crown rail (`Donchian21 + EMA8 + RSI75`) scores **−0.406** on BTC next-open. The meta does not transfer — re-earned from probes.

## R7 probes (crypto_fx_lab.py)

| Probe | Entry change | Score | Key insight |
|---|---|---:|---|
| R6 s01 clone | Don21 + EMA8 | −0.406 (BTC) | Too slow for crypto gap risk |
| `_probe_don8` | Don8 + EMA8 | **0.134** | Tighter channel lifts SOL/ADA |
| `_probe_trail` | + `TrailingStop(0.08)` stmt | 0.090 | Stmt templates compile via gene-runner |
| `_probe_dual_path` | + EMA cross OR-path | 0.170 | FX cross path blocked by cascade onBar |
| `_probe_cross_exit` | crossunder exit | −0.162 | FX trades but bleeds Sharpe |

**Winner rail:** `close > ema(8) && donchianHigh(8)` + cascade RSI72 + **8% TrailingStop** + `falling(hist, 3, 5)` minBars gate.

## R7 thesis: maximalist templates, crypto-tuned shell

Keep layered `onPosition` identity. Ship **real stmt-template invocations** (P0 wish closed):

- `TrailingStop(0.08)` — s01–s03, s05
- `TimeExit(21|34)`, `ProfitLock`, `StagedProfitLock`, `DualRsiScalpExit`, `AtrChandelierExit`, `StagedDonchianExit`, `DualMacdConfirm`, `TrailBelowEma`

Use new **`falling(x, n, minBars)`** third arg to gate MACD slope exits without duplicating `bars_in_trade >= k &&`.

## R7 arsenal

| File | Name | Core thesis | Stmt calls | Score |
|---|---|---|---|---:|
| `s01.ms` | StmtRailDon8R7 | Don8 rail + **TrailingStop/TimeExit/ProfitLock/TrailBelowEma** | 4 | 0.170 |
| `s02.ms` | FallGatedDon8R7 | s01 + **`falling(m8.hist,3,5)`** + slower MACD fall | 4 | **0.171** |
| `s03.ms` | StagedDualRsiR7 | s02 rail + **StagedProfitLock + DualRsiScalpExit** stmt | 6 | 0.171 |
| `s04.ms` | AtrChandelierR7 | s02 + **AtrChandelierExit** stmt (EquityHardStop alias) | 5 | 0.171 |
| `s05.ms` | MaximalistCrownR7 | Full stack: 8 stmt templates + dual fall gated | **8** | 0.171 |

s02–s05 converge on 3m eval — extra layers no-op when fall-gated rail dominates (same R6 pattern, new domain).

## Per-symbol highlights (s02 flagship)

| Symbol | Sharpe | vs BH | Trades | Note |
|---|---:|---:|---:|---|
| **ADAUSD** | 1.866 | **+3.678** | 4 | Best crypto runner |
| **SOLUSD** | 1.646 | +2.123 | 8 | Don8 captures vol bursts |
| **USDCAD** | 2.555 | −0.792 | 4 | Positive abs Sharpe, loses vs BH |
| **EURUSD** | 0.000 | **+3.261** | 0 | Don8 never fires — cash beats FX drift |
| BTCUSD | −1.279 | +0.301 | 10 | Beats BH but negative abs |
| ETHUSD | −2.607 | −0.896 | 8 | Worst crypto laggard |

## Adaptations from equity R6

| Equity pattern | Crypto+FX fix |
|---|---|
| Donchian21 entry | **Donchian8** — fills gap before next-open whipsaw |
| 5% hard stop | **8% TrailingStop** stmt — crypto daily range |
| RSI75 take-profit | **RSI72** — faster exit on mean-revert spikes |
| `falling(hist, 3)` | **`falling(hist, 3, 5)`** — minBars avoids entry-bar noise |
| EMA8 entry confirm | **Kept** — still filters false Don8 breaks |

## What we still cannot solve (→ WISHLIST)

1. **FX participation** — EMA cross fires on EUR (2 trades pure-cross) but cascade onBar suppresses; need asset-class param or regime gate
2. **WF collapse** (−1.32) — crypto walkforward windows unlike equity bull tape
3. **Layer redundancy** — s03/s04/s05 identical to s02 on 3m; no fire diagnostics yet
4. **Partial exits** — RSI72 take-profit all-or-nothing on violent crypto spikes

## Flagship

**`round-07/s05.ms`** — maximalist mandate: 8 live stmt-template invocations + dual `falling(..., minBars)` gates. Score tied with s02 at 0.171; kept for template catalog depth and OOS differentiation bet.
