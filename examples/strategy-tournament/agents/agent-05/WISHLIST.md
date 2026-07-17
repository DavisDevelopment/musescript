# Agent 05 — MuseScript Builtin Wishlist

Breakout systems need richer volatility, volume, and position-state primitives. R5 proved EMA8 entry + `cascadeExit` OR chains + `falling(hist,n)` onPosition can reach score **1.549** without volume — but template boilerplate and exit-priority semantics remain painful. R6 confirmed the crown is stable: staged Donchian and ATR locks are neutral; RSI78 and EMA5+fall2 are confirmed traps.

## R5 language friction (new)

| Gap | Workaround used | Impact |
|-----|-----------------|--------|
| No native `donchian()` struct | Hand-rolled `highest(high,n)` / `lowest(low,n)` templates | 8–12 lines prelude per strategy |
| No exit-priority / first-match | Duplicate MACD bindings (`m` + `m8`) in every strategy | Error-prone when tuning windows |
| `falling()` scope ambiguous | Must place on `onPosition` not `onBar` (+0.08 score) | Easy to mis-wire; no compile hint |
| No `cascade()` combinator | Manual `\|\|` chains in templates | Works but verbose across 5 variants |
| RSI threshold not parameterized at runtime | Hard-coded 72 vs 75 in separate files | Probe-only tuning; no sweep syntax |

## Volume & participation

| Builtin | Use case | R7 status |
|---------|----------|-----------|
| `volume` series | Breakout confirmation: `volume > sma(volume, 21)` on 21-high break | **Shipped** — works on crypto; FX Yahoo tapes are all zero |
| `relative_volume(n)` | Normalized participation spike vs trailing average | **Still missing** — hand-roll: `volume <= 0 \|\| volume > sma(volume, n)` |
| `obv(close, volume)` | Accumulation before Donchian break | Not available |
| `vwap()` | Institutional anchor — only long breaks above session/week VWAP | Available but unused in R7 |

## Volatility & squeeze

| Builtin | Use case |
|---------|----------|
| `bb_width(close, n, k)` | Bollinger bandwidth for squeeze rank (cleaner than hand-rolled ATR ratios) |
| `keltner_channel(n, m)` | ATR envelope break parallel to Donchian |
| `atr_percentile(n, lookback)` | Regime-aware squeeze: enter only when ATR in bottom decile |
| `chandelier_exit(n, mult)` | Native ATR trail from highest-high since entry (vs manual `entry_price - k*atr`) |

## Donchian / channel

| Builtin | Use case |
|---------|----------|
| `donchian(high, low, n)` → `{upper, lower, mid}` | Avoid repeating `highest`/`lowest` pairs; enable mid-channel stop |
| `highest_excluding_current(high, n)` | True prior-bar breakout (eliminates same-bar look-ahead debate) |
| `breakout_strength(close, n)` | Close distance above channel as position-sizing input |

## Position state

| Builtin | Use case |
|---------|----------|
| `bars_since_flat()` | Cooldown after loss before re-entry |
| `last_trade_pnl()` | Skip re-entry after consecutive Donchian failures (META fix) |
| `partial_flat(fraction)` | Staged exits: 50% at 8-low, remainder at 13-low |
| `trail_stop(type, mult)` | Declarative ATR/Donchian trail in `onPosition` without manual algebra |

## Multi-timeframe (even synthetic)

| Builtin | Use case |
|---------|----------|
| `daily_trend(symbol)` | Weekly/daily EMA slope gate for 3m-window daily bars |
| `resample(series, factor)` | 5-bar “weekly” Donchian overlay on daily tape |

## Highest-impact trio for Agent 05

1. **`relative_volume(n)` + `asset_class()`** — volume series exists but FX is zero; need native normalized vol + asset-aware branching
2. **`donchian()` struct + `atr_squeeze(f, s, ratio)`** — R7 winner is hand-rolled ATR834 + highest/lowest pairs
3. **`min_trades` scoring guard + `bars_since_flat()`** — prevent flat-vs-BH score inflation; cooldown after failed breaks

## R5-discovered high-impact additions

4. **`cascade(exits[])` or `any_of(template...)`** — declarative OR-chain for exit stacks; eliminates 4-line template prelude per strategy
5. **`exit_scope(onBar | onPosition)` hint** — compiler warning when `falling()` placed on wrong block (R5: +0.08 score from scope fix alone)

## R6 language friction (final round)

| Gap | Workaround used | Impact |
|-----|-----------------|--------|
| No staged Donchian primitive | `bars_in_trade >= 5 && bars_in_trade < 8 && donchianLow(8)` in onPosition | **Neutral** — 13-low cascade fires before early window activates |
| No ATR profit-lock helper | `close > entry_price + 2 * atr(close, 8)` manual | **Neutral** — calibrates identically to 3% equity lock on 3m tape |
| No RSI threshold sweep | Separate s01/s02 files for 75 vs 78 | RSI78 confirmed anti-pattern (−0.34 score); need param sweep syntax |
| `partial_flat` missing | Full flat only — staged exit is all-or-nothing | Blocks true 8-low early / 13-low late architecture |
| EMA5 vs EMA8 not composable | Duplicate strategy files | EMA5 + fall2 −0.26 score vs crown; need entry-filter struct |

## R6-confirmed high-impact additions

6. **`partial_flat(fraction)` + `exit_priority`** — unlock staged Donchian (8-low scalp + 13-low runner) without cascade pre-emption
7. **`atr_profit_target(mult, window)`** — declarative vol-scaled lock; R6 shows 2×ATR8 ≡ 3% on current window but diverges on higher-vol tapes
8. **`falling(series, n, min_bars)`** — fuse `bars_in_trade >= k && falling(hist, n)` into one scoped exit (fall2 premature without min_bars guard)
9. **RSI vault compile-time lint** — warn when vault > 76 on momentum baskets (RSI78 destroyed QQQ Sharpe 4.50→1.68)

## R7 crypto+FX friction (causal next-open)

| Gap | Workaround used | Impact |
|-----|-----------------|--------|
| No `relative_volume(n)` builtin | `volume <= 0 \|\| volume > sma(volume, n)` template | **Neutral** on FX (Yahoo volume always 0); inert vs squeeze834 on eval window |
| `volume` present but FX is zero | Passthrough guard on volume filter | FX symbols never blocked; crypto can still gate |
| Equity cascade dead on BTC causal | Drop MACD/RSI cascade; return to pure Donchian/ATR | R6 crown −0.41 BTC → squeeze834 +0.59 basket |
| Stmt templates for exit stacks | `TrailingStop`, `TimeCap`, `AtrFallExit` bare calls | **Shipped gift works** — cleaner onPosition layering |
| `falling(x, n, minBars)` | `falling(a8, 3, 8)` vol-expansion exit | **+0.11 score** vs squeeze834; fall2/min5 too early |
| Score rewards flat vs negative BH | s05 only 2 trades (USDJPY) | Inflated 0.705 — need min-trades lint or participation floor |

## R7-confirmed high-impact additions

10. **`relative_volume(n)` builtin** — replace hand-rolled passthrough; detect weak FX volume and skip filter automatically
11. **`asset_class()` or `volume_available()`** — branch crypto participation filter vs FX ATR-only path in one strategy file
12. **`min_trades` scoring guard** — penalize zero-trade symbols so flat-vs-BH cannot dominate leaderboard
13. **`donchian(n)` struct** — still highest boilerplate cost; every R7 file repeats High/Low templates
14. **`atr_squeeze(fast, slow, ratio)`** — one-liner for `atr(f) < atr(s) * ratio` pattern that won R7
