# MuseScript Wishlist — Agent 04 (Mean Reversion / Divergence)

Features needed to express true mean-reversion and multi-timeframe logic that RSI strategies require but current MuseScript cannot encode cleanly.

## 1. Stateful setup memory (`bars_since` / `once`)

**Problem:** R4 probe `lowest(rsi(close,13), 8) < 38 && high >= highest(high, 21)` never fired — dip and breakout occur on *different* bars, but we cannot express "breakout within N bars of a prior dip" without persistent state.

**Need:**
```javascript
when rsi(close, 13) < 38: mark("dip")
when bars_since("dip") <= 8 && high >= highest(high, 21): long()
```

Or `once(condition)` latch that clears on flat().

## 2. Pivot / swing helpers for divergence

**Problem:** s04 uses crude proxy `close > close[8] && r < r[8]`. Real bullish divergence needs local minima on price and RSI at different offsets.

**Need:**
```javascript
pl = pivotlow(close, 5, 5)
rl = pivotlow(rsi(close, 13), 5, 5)
when pl > pl[1] && rl < rl[1]: // true bullish divergence
```

Without pivots, divergence strategies stay 2-trade noise on 63-bar tapes.

## 3. Multi-timeframe (`request.security` / `htf`)

**Problem:** BRIEF mandate says "gate dips with higher-timeframe trend" but we only have daily bars. EMA(34) on daily ≈ 7-week trend; no weekly RSI or weekly EMA(13) for oversold context.

**Need:**
```javascript
w_rsi = htf(rsi(close, 13), "1W")
when daily_rsi < 40 && w_rsi > 45: long()  // daily dip in weekly uptrend
```

## 4. RSI series in `lowest()` / `highest()` reliably

**Problem:** `lowest(r, 8)` on assigned variable `r = rsi(...)` may not track as expected (p08/p18 zero-trade probes). Had to inline `lowest(rsi(close,13), 8)` — documentation unclear on whether indicator assignments propagate through windowed reducers.

**Need:** Explicit guarantee that `x = rsi(close, 13); lowest(x, 8)` ≡ `lowest(rsi(close, 13), 8)`, or a dedicated `rsi_lowest(period, window)` helper.

## 5. Entry-once / re-entry cooldown

**Problem:** s03 without `position() == 0` churns 24 trades with negative Sharpe; with guards, s01 drops to 12. No native `cooldown(5)` after flat to prevent re-entering the same dip zone repeatedly.

**Need:**
```javascript
when flat() && cooldown(5) && r < 40: long()
```

## 6. Partial / scaled exits

**Problem:** Mean-reversion wants scale-out: half at RSI 55, rest at Donchian high. Only `long()` / `flat()` exist.

**Need:** `reduce(0.5)` or target-based exit blocks.

## 7. `crossover` on arbitrary expressions

**Problem:** Recovery entries use manual `r > 35 && r[1] <= 35`. Works, but noisy vs `crossover(rsi(close,8), 35)`.

**Need:** `crossover(rsi(close, 8), 35)` and `crossunder` on scalar thresholds, not just two series.

## 8. Boolean `or`/`and` aliases

**Problem:** Tournament rules mandate `&&`/`||` but complex dip/recovery conditions become unreadable. Minor — rules are clear — but parenthesis nesting errors caused several R3 zero-trade strategies.

**Need:** Either alias support or a `all(a, b, c)` / `any(a, b, c)` variadic helper.

## 9. `falling()` / `rising()` on RSI series (R5–R6 probe)

**Problem:** R5 s05 probe `falling(r, 2)` on assigned `r = rsi(close, 13)` in onPosition did not differentiate from s03 (identical score 1.382). R6 retest: s04 (dual RSI cascade + `falling(r13,3)` + `falling(r8,2)`) scores **identical** to s02 (1.532) — slope fires but cascade already exits first. However, s05 layers slope **after** MACD anchor trail and gains **+0.070** over s02 (1.602 vs 1.532).

**Need:**
```javascript
r = rsi(close, 13)
when falling(r, 3) && r < 55: flat()   // RSI momentum decay exit
```

**R6 finding:** `falling()` works on RSI assignments (inline `r13 = rsi(close,13)` in strategy body). Slope is a *secondary* exit — useful only in deep onPosition stacks, not as primary onBar substitute for RSI>75 TP.

## 10. Template lag indexing on RSI (`rsi(...)[1]`)

**Problem:** R5 s04 `rsiRecoveryCross` template using `rsi(close, len)[1]` inside a template produced **zero trades**. Inline `r = rsi(...); r[1]` in strategy body works. Template-level `[1]` on nested indicator calls may not propagate.

**Need:** Consistent lag semantics in expr templates, or explicit `rsi_lag(period, bars)` helper.

## 11. Dual RSI asymmetric thresholds (R6 validated)

**Problem:** Single-period RSI(13)>75 misses fast overbought on RSI(8). R6 dual cascade `rsi(13)>75 || rsi(8)>78` plus failure `rsi(13)<35 || rsi(8)<32` lifts composite from 1.427 → 1.532 (s02) and 1.602 with MACD layer (s05).

**Need:** Native `rsi_dual(fast, slow, tp_fast, tp_slow, fail_fast, fail_slow)` template or band struct to reduce cascade boilerplate.

## 12. RSI band entry gates (R6 dead end)

**Problem:** R6 s03 probe `rsiInBand(13, 40, 68)` on Donchian entry scored 0.184 (26 trades). Band filters reject too many breakouts on bull 3m tape. Dual recovery cross (s03 v2) trades but scores 0.137 — mandate entry path still dead.

**Need:** `bars_since` dip memory before band/cross entry can work (see #1).

## Priority for Agent 04

1. **bars_since / setup memory** — still the biggest miss; R6 s03 dual recovery scores 0.137 vs exit-only s05 at 1.602; R7 s03 with vol gate scores 0.416 vs s05 at 0.672
2. **pivotlow/pivothigh** — unlocks real divergence (R4 s04 dead; R5–R6 abandoned)
3. **htf()** — unlocks proper trend filter per BRIEF mandate; daily EMA834 insufficient for recovery timing; R7 uses ATR/close vol gate as workaround
4. **crossover(rsi, level)** — cleaner recovery entries (s03 uses manual `r8[1]` inline; template lag still broken)
5. **falling(rsi, N, minBars)** — **works** as secondary onPosition exit; R7 s04/s05 layered stack
6. **dual RSI template** — validated R6/R7 edge; reduce cascade duplication across strategies
7. **Stmt templates** — **shipped R7**; `EquityHardStop` + `ProfitLock` expand cleanly in s05

## 13. Volatility regime gate (R7 validated workaround)

**Problem:** R6 Donchian breakout crown scores −0.64 on BTC next-open. Naive RSI dip-buy loses on crypto whipsaw (−1.7 Sharpe). No native `is_crypto` / asset-class switch exists.

**Workaround (R7):**
```javascript
vol = atr(close, 14) / close
when position() == 0 && vol < 0.015 && rsi(close, 13) < 42: long()
```

**R7 finding:** ATR/close < 1.5% gates out all 5 crypto symbols (0 trades) while allowing FX RSI scalps. Composite lifts from −0.19 (R6 crown) to **+0.672** (s05). BTC score: −0.64 → **+0.656**.

**Need:** Native `regime("range")` / `relative_vol(n)` helper so vol gate isn't hand-tuned per domain. Or asset metadata on tape for explicit crypto vs FX branching.
