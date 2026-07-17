# Agent 01 — MuseScript Wishlist (Round 4)

Features we wanted while building R4 micro-cross + stolen-exit hybrids.

---

## 1. `onPosition` indicator bindings

**Proposed signature:**
```muse
onPosition {
  m = macd(close, 8, 21, 5)   // evaluate in position hook scope
  when m.hist < 0: flat()
}
```

**Why:** MACD exit-only (agent-03 pattern) requires computing `m` in `onBar` and referencing it in `onPosition`. This works but is fragile — unclear whether `m` is re-evaluated at position-hook time or frozen from bar open. We want explicit position-scoped indicator evaluation.

**Example that hurt:**
```muse
onBar {
  m = macd(close, 8, 21, 5)
  when e8 > e34 && high >= highest(high, 21): long()
  when low <= lowest(low, 13): flat()
}
onPosition {
  when m.hist < 0: flat()   // is this bar-close hist or entry-bar hist?
}
```

---

## 2. Staged / conditional exit templates

**Proposed signature:**
```muse
template StagedDonchianExit(warm: Int, tight: Int, wide: Int) {
  onPosition {
    when bars_in_trade >= warm && low <= lowest(low, tight): flat()
    when bars_in_trade < warm && low <= lowest(low, wide): flat()
  }
}
```

**Why:** agent-05 probes used 8-bar tight exit after warmup; implementing this inline duplicates `lowest()` calls and `bars_in_trade` guards across five strategies. A stmt-template with parameterized staged exits would keep risk shells DRY.

**Example we wanted:**
```muse
strategy S05 {
  StagedDonchianExit(8, 8, 13)
  onBar { /* entry */ }
}
```

---

## 3. `rising()` / `falling()` on indicator series

**Proposed signature:**
```muse
rising(ema(close, 8), 2)   // slope of any numeric series
falling(macd(close,8,21,5).hist, 3)
```

**Why:** s05 `Ema834RisingMacdPos` used `rising(close, 2)` as entry filter and produced **zero SPY trades** — price rising is too strict at Donchian break. We wanted `rising(ema(close,8), 2)` to gate on micro-cross momentum instead, but `rising()` only accepts OHLCV series, not computed indicators.

**Failed snippet:**
```muse
when e8 > e34 && rising(close, 2) && high >= highest(high, 21): long()
// 0 trades on SPY — wanted rising(e8, 2) instead
```

---

## 4. Entry-once / re-arm semantics for `crossover`

**Proposed signature:**
```muse
when crossover_once(fast, slow, rearm: crossunder(fast, slow)): long()
```

**Why:** `crossover(fast, slow) && high >= highest(high, 21)` fires only on the exact bar of the cross *and* Donchian break aligning — often 0–2 trades per 63-bar tape. We want a latch: arm on cross, enter on first subsequent Donchian confirm, disarm on crossunder.

**Example gap:**
```muse
// s03 gets 2 SPY trades — good Sharpe but fragile sample
when crossover(fast, slow) && high >= highest(high, 21): long()
// wanted: cross arms, donchian confirms within N bars
```
