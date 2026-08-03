# MuseScript Language Wishlist — Tournament Aggregate (R4–R6)

Compiled from all six agents' `WISHLIST.md` files. Ranked by how many agents independently requested each feature and by demonstrated score impact.

## Shipped for Cycle 2 (crypto + FX)

| Feature | Status |
|---|---|
| Working stmt-template invocation through gene-runner | **Shipped** — expand before seedInterp; `TrailingStop(0.05)` no longer throws |
| Causal fills (`next-open`) | **Shipped** — signal at bar t close, fill at t+1 open before OHLCV exposure |
| `falling`/`rising` with optional `minBars` | **Shipped** — `falling(x, n, minBars)` gated by `bars_in_trade` |
| Composite score + WF in crypto/FX `--eval` | **Shipped** — `crypto_fx_lab.py` returns `score` + `wf_mean_sharpe` |
| Yahoo FX as real OHLC (not ECB mid) for official tapes | **Shipped** — Stooq → Yahoo → Frankfurter chain; mid_as_ohlc rejected from official scoring |

## Shipped for Cycle 3 (language extensions, 2026-08)

| Feature | Status |
|---|---|
| **ATR / chandelier trailing stop** (was P1, req. 05/06) | **Shipped** — `trail(dist)` peak-following stop; `when trail(2 * atr(close, 14)): flat()` |
| **Parameter sweep syntax** (was P1, req. 02/05) | **Shipped** — `param fast = 8 { values: [5, 8, 13, 21] }` explicit non-uniform grid via `--optimize` (the `sweep(…)` idea, as an options-block list) |
| **Per-instrument conditionality** | **Shipped** — `asset_is("crypto")` / `symbol_is(…)` + variadic `asset_in(…)` / `symbol_in(…)`; one uniform strategy branches by instrument (reads the tape's asset/symbol columns) |
| **N-of-M confirmation / bool→number** | **Shipped** — `count_true(a, b, c) >= 2` (variadic vote); also a plain `0/1` coercion |
| **In-trade analytics** | **Shipped** — `highest_since_entry(?field)` / `lowest_since_entry(?field)` / `return_since_entry()` |
| **Regime-strength gates** | **Shipped** — `slope(series, n)` (signed OLS trend), `zscore_roll(series, n)`, `percent_rank(series, n)` |
| **Fail-open corpus seeding** | **Shipped** — hand-written strategies with `onPosition` stops + multi-output fields (`rising(m.hist,3)`, 3-arg `falling`) now seed the evo run verbatim via an opaque `BFeature` leaf (was silently skipped) |

Still open from this batch: **`bars_since` / setup memory**, **partial / staged exits** (`flat(0.5)`),
**multi-timeframe** (`htf`/`resample`), **exit-layer firing diagnostics**, and a **`donchian(…)` struct**.

## P0 — still open / partially open

| Feature | Proposed | Requested by | Evidence |
|---|---|---|---|
| **Exit-layer priority / firing diagnostics** | Tagged exits `flat("profit_lock")` + per-layer fire counts | 01, 03, 05, 06 | R5/R6 silent no-op layers |
| **Composite score in equity `tournament_lab --eval`** | Parity with crypto_fx_lab | 01, 02, 03, 06 | Equity harness still needs one-shot score JSON |

## P1 — requested by 2–3 agents

| Feature | Proposed | Requested by | Status |
|---|---|---|---|
| Partial / staged exits | `flat(0.5)` / `partial_flat(fraction)` | 04, 05, 06 | open |
| Donchian struct | `donchian(high, low, n) -> {upper, lower, mid}` | 03, 05 | open |
| Chandelier / ATR trail builtin | `chandelier_exit(8, 2)` | 05, 06 | → **Shipped** as `trail(2*atr(close,14))` |
| Cascade combinator | `any_of(...)` exit chains | 01, 05 | partially covered by `count_true(...)` voting |
| Parameter sweep syntax | `param rsiHi = sweep(72, 75, 78)` | 02, 05 | → **Shipped** as `{ values: [72, 75, 78] }` |
| Setup memory / `bars_since` | `mark("dip")` + `bars_since("dip") <= 8` | 04, 06 | open |
| Multi-timeframe | `htf(...)` / `resample(...)` | 04, 05, 06 | open |

## Empirically resolved

- Equity cascade meta does **not** transfer to causal crypto/FX (R6 crown → BTC score −0.64 under next-open)
- MACD entry gates were toxic on the equity tape; exits-only remains the safer default
- Donchian idiom: `high >= highest(high, N)` / `low <= lowest(low, N)`
