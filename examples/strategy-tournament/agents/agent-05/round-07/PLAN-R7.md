# Round 7 Plan — Agent 05 (Donchian / ATR Breakout Hunter)

**Domain:** crypto + forex · **Eval:** 2026-04-14 → 2026-07-13 · **Execution:** next-open only

## Context

Equity-cycle crown (`round-06/s01.ms`, score **1.549**) **does not transfer**. On causal BTC next-open the same shell scores **−0.41** — MACD/RSI cascade entries fire into next-open slippage on high-beta crypto.

Pure Donchian (`round-01/s05.ms`) still beats BTC in isolation (+1.91 ΔSharpe) but the 10-symbol basket score is **−0.21** because FX and altcoin whipsaw dominate.

## Hypothesis

1. **Causal fills punish naive breakouts** — need volatility contraction (ATR squeeze) before Donchian entry so expansion is real, not same-bar noise.
2. **ATR8/34 beats ATR13/55** on this window — faster vol ratio (`a8 < a34 * 0.89`) lifts mean Sharpe from −0.01 → **+0.25**.
3. **Volume filter is FX-safe** — Yahoo FX tapes report `volume=0`; `volume <= 0 || volume > sma(volume, 21)` passes FX, confirms crypto participation (neutral vs squeeze834 alone on this window).
4. **`falling(atr, 3, 8)` exit** — new minBars gift cleanly exits vol-expansion trades after 8 bars without premature fall2 whipsaw (+0.11 score vs squeeze834 base).

## Probe ladder (21 variants → 5 shipped)

| Stage | Probe | Score | Finding |
|------:|-------|------:|---------|
| baseline | R1 Don21/13 | −0.21 | Theory anchor; basket bleed |
| baseline | R6 EMA8 cascade | −0.41 | Equity crown dead on BTC causal |
| vol | ATR13/55 squeeze + Don21 | 0.473 | Squeeze unlocks FX/crypto mix |
| vol | ATR8/34 squeeze + Don21 | **0.592** | Faster ratio wins |
| exit | + `falling(a8,3,8)` | **0.705** | Flagship — stmt `AtrFallExit` |
| trap | EMA8 entry gate | −0.35 | Confirms R6 EMA confirm hurts |
| trap | Don13 fast channel | 0.127 | Too many FX false breaks |

## Shipped strategies

| File | Name | Role | Score |
|------|------|------|------:|
| s01 | Donchian21x13CausalR7 | Pure Donchian + stmt `TrailingStop`/`TimeCap` | −0.21 |
| s02 | AtrSqueezeDon21R7 | Classic ATR13/55 squeeze → Don21 | 0.473 |
| s03 | Atr834SqueezeDon21R7 | ATR8/34 squeeze → Don21 | 0.592 |
| s04 | VolSqueeze834R7 | s03 + `relativeVolOk` passthrough | 0.592 |
| s05 | Squeeze834FallFlagshipR7 | s03 + `AtrFallExit(8,3,8)` + profit lock | **0.705** |

## Language gifts used

- **Stmt templates:** `TrailingStop`, `TimeCap`, `AtrFallExit` (bare invocation, gene-runner expand)
- **`falling(x, n, minBars)`:** `falling(a8, 3, 8)` in s05 onPosition layer
- **`&&` / `||`:** squeeze gate, volume passthrough, Donchian OR exits
- **Fib windows only:** 8, 13, 21, 34, 55

## R7 verdict

Best: **`round-07/s05.ms`** — score **0.705**, mean ΔSharpe **+1.28**, median MDD **0%**.

Caveat: s05 is highly selective (2 trades on USDJPY, flat elsewhere) — score is driven by avoiding negative buy-and-hold on most symbols. s03 is the better *active* breakout (positive mean Sharpe, broader participation).

Re-earn path for R8: loosen squeeze ratio on crypto-only subset or dual-channel (Don21 entry / Don13 scout) while keeping ATR834 core.
