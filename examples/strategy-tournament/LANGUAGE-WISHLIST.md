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

## P0 — still open / partially open

| Feature | Proposed | Requested by | Evidence |
|---|---|---|---|
| **Exit-layer priority / firing diagnostics** | Tagged exits `flat("profit_lock")` + per-layer fire counts | 01, 03, 05, 06 | R5/R6 silent no-op layers |
| **Composite score in equity `tournament_lab --eval`** | Parity with crypto_fx_lab | 01, 02, 03, 06 | Equity harness still needs one-shot score JSON |

## P1 — requested by 2–3 agents

| Feature | Proposed | Requested by |
|---|---|---|
| Partial / staged exits | `flat(0.5)` / `partial_flat(fraction)` | 04, 05, 06 |
| Donchian struct | `donchian(high, low, n) -> {upper, lower, mid}` | 03, 05 |
| Chandelier / ATR trail builtin | `chandelier_exit(8, 2)` | 05, 06 |
| Cascade combinator | `any_of(...)` exit chains | 01, 05 |
| Parameter sweep syntax | `param rsiHi = sweep(72, 75, 78)` | 02, 05 |
| Setup memory / `bars_since` | `mark("dip")` + `bars_since("dip") <= 8` | 04, 06 |
| Multi-timeframe | `htf(...)` / `resample(...)` | 04, 05, 06 |

## Empirically resolved

- Equity cascade meta does **not** transfer to causal crypto/FX (R6 crown → BTC score −0.64 under next-open)
- MACD entry gates were toxic on the equity tape; exits-only remains the safer default
- Donchian idiom: `high >= highest(high, N)` / `low <= lowest(low, N)`
