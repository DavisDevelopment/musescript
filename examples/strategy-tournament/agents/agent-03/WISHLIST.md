# Agent 03 — Language Wishlist

## Resolved since equity cycle (thank you)

- [x] Statement templates expand through gene-runner (`TrailingStop`, `HardStop`, `TimeStop`)
- [x] `falling(x, n, minBars)` / `rising(x, n, minBars)` — used in s03/s05
- [x] Causal `next-open` execution mode
- [x] `--eval` returns composite `score` + `wf_mean_sharpe` on crypto/FX harness

## Still needed (Round 7 walls)

### Asset-class param profiles

Crypto and FX need different MACD periods and stop widths in the **same** strategy file.
Wish: `@profile(crypto)` / `@profile(forex)` param blocks, or `when asset == "crypto"` from tape
metadata.

### Entry cooldown / `bars_since`

After a flat exit, MACD re-entries whipsaw on BTC next-open. Want `bars_since(flat) >= 3` memory
without hand-rolling state.

### Donchian lookback clarity

`high >= highest(high, 21)[1]` produced **zero trades** in R7 testing; current-bar
`highest(high, 21)` always fires. Need either Pine-style `[1]` offset on channel indicators or
`highest(high, 21, exclude_current=true)`.

### Partial exits

Equity crown uses layered exits (Donchian + MACD + RSI). Single `flat()` all-or-nothing leaves
profit on the table in crypto trends. Want `flat(0.5)` or scale helpers.

### Relative volume confirmation

Crypto tapes have real volume; FX volume is weak. A `relative_volume(n)` helper would let MACD
entries require participation without agent-05's full breakout identity.

### Exit-layer fire diagnostics

When stacking `||` exit cascades, no visibility into which clause fired. Debug hook or per-clause
counters would speed iteration.

## Round 7 takeaway

Dual-MACD cascade is dead on BTC causal fills. Single MACD + `falling(hist, n, minBars)` + stmt
template risk shells is the viable path forward.
