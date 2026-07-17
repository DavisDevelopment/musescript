# Agent 01 — Round 4 Plan

## R3 recap

| Strategy | Score | vs BH | Key issue |
|---|---:|---:|---|
| s01 Ema834DonchianT13 | **0.964** | +0.011 | EMA crossunder on `onBar` clipped winners; matched agent-02 tie |
| s03 Ema834MacdGate | 0.964* | +0.011 | MACD on `onBar` exit = same pathology as s01 |
| s05 Ema834FullR3 | — | — | MACD + EMA crossunder double-clip |

*Podium tie; plateau at **1.002** held by pure Donchian (agent-05/06). Best vs-BH remains agent-03 MacdDonchian (+0.075).

**Breakthrough insight:** agent-03 `MacdDonchianExitOnly` moves MACD flat to `onPosition` only — Donchian 13 handles structural exit on `onBar`, MACD trims momentum decay without blocking re-entry. Removing EMA crossunder from `onBar` flat lets trades ride like the winner.

## What we stole (R4)

| Source | Pattern | Applied in |
|---|---|---|
| **agent-03 / s04** | MACD hist exit **only** in `onPosition` | s01, s03, s04, s05 |
| **agent-05 / s01** | Donchian 21 entry / 13 exit + T13 + 5% hard stop | all five |
| **agent-03 / s02** | EMA 8/34 gate on Donchian entry (not MACD onBar) | s01 |
| **agent-02 / s03** | `crossover(fast, slow)` event entry + Donchian confirm | s02, s03 |
| **agent-03 / s02** | `mom(close,8)` lazy dual exit in `onPosition` | s05 |
| **Our R1 s05** | EMA 8/34 micro-cross identity | s01–s03, s05 |
| **Our BRIEF** | Faster EMA 8/13 pair | s04 |

## What we kept

- **Core theory:** every entry requires SMA/EMA micro-cross (level `e8 > e34`, `crossover(fast,slow)`, or `e8 > e13`).
- **No pure Donchian** — breakout confirm is additive, not the thesis.
- **Fib windows only:** Donchian 21/13, T13, MACD (8,21,5).

## R4 iteration thesis

1. **Decouple entry from exit** — micro-cross + Donchian for entry; Donchian 13 + position hooks for exit. Drop EMA crossunder from `onBar`.
2. **MACD as position hook** — stolen exit-only placement lifts SPY vs-BH from −0.33 (R3 s01) to **+0.59** (R4 s03 self-test).
3. **Crossover precision** — s03 uses `crossover(ema8, ema34)` at Donchian break for fewer stale level entries.
4. **Risk shell unchanged** — T13 + 5% equity stop (proven plateau stack).

## R4 lineup

| File | Strategy | Hypothesis |
|---|---|---|
| s01.ms | Ema834MacdPosExit | Flagship: EMA 8/34 level + Donchian + MACD position exit |
| s02.ms | Ema834CrossDonchian | Crossover entry, Donchian exit only — no MACD filter |
| s03.ms | Ema834CrossMacdPos | Crossover + MACD pos exit — best SPY self-test (+0.59 vs BH) |
| s04.ms | Ema813MacdPosExit | Faster EMA 8/13 micro pair, same exit shell |
| s05.ms | Ema834MomMacdPos | Lazy dual exit: MACD + mom both negative before flat |

## SPY 3m self-test (2026-04-14 → 2026-07-13)

| File | Sharpe | vs BH | MDD | Trades |
|---|---:|---:|---:|---:|
| R3 s01 | 1.97 | −0.33 | 3.7% | 3 |
| s01 | 2.54 | **+0.25** | 2.2% | 5 |
| s02 | 2.34 | +0.04 | 3.0% | 2 |
| s03 | **2.88** | **+0.59** | 1.9% | 2 |
| s04 | 2.54 | +0.25 | 2.2% | 5 |
| s05 | 2.00 | −0.29 | 3.6% | 3 |

**Target:** break 1.002 plateau via lifted mean d-Sharpe (MACD pos exit) while preserving micro-cross mandate. s03 is primary bet; s01/s04 provide cross-symbol breadth.
