# Agent 02 — MuseScript Wishlist (Round 4)

Features we wanted while building EMA 8/13 gate + Donchian vault hybrids.

---

## 1. `rising()` / `falling()` on EMA series

**Proposed signature:**
```muse
rising(ema(close, 8), 2)    // slope of any computed series
falling(ema(close, 13), 3)
```

**Why:** We wanted `e8 > e13 && rising(e8, 2)` as a momentum-quality gate softer than crossover but stricter than static alignment. `rising()` only accepts OHLCV fields, not indicator outputs — forced us to use static `e8 > e13` instead.

**Example we wanted:**
```muse
when e8 > e13 && rising(e8, 2) && high >= highest(high, 21): long()
// blocked — rising(e8, 2) not supported
```

---

## 2. Cross-arm / delayed Donchian confirm

**Proposed signature:**
```muse
when cross_arm(fast, slow, confirm: high >= highest(high, 21), expire: 8): long()
```

**Why:** s05 `Cross813Donch21R4` requires `crossover(8,13)` and Donchian break on the **same bar** — only 0–2 SPY trades. We wanted: arm on golden cross, enter on first Donchian 21-high within 8 bars, disarm on crossunder.

**Failed pattern (score 0.763):**
```muse
when position() == 0 && crossover(fast, slow) && high >= highest(high, 21): long()
// 2 SPY trades — wanted cross-then-break within N bars
```

---

## 3. Tiered EMA alignment helper

**Proposed signatures:**
```muse
ema_stack(bull: List<Int>) -> Bool   // e8 > e13 > e21 > e34
ema_above(price: Series, periods: List<Int>) -> Bool
```

**Why:** R4 breakthrough came from discovering EMA 8/13 beats 8/34. We grid-searched `{5,8,13,21,34}` manually in 21 probe files. A stack helper would express cascade filters without five assignment lines.

**Winning inline code we repeat:**
```muse
e8 = ema(close, 8)
e13 = ema(close, 13)
when e8 > e13 && high >= highest(high, 21): long()
// wanted: when ema_stack([8, 13]) && donchian_break(21): long()
```

---

## 4. Trailing EMA stop in `onPosition`

**Proposed signature:**
```muse
onPosition {
  when close < ema(close, 13): flat()   // or trail_ema(13)
  when bars_in_trade >= 13: flat()
}
```

**Why:** p15 `Ema813EmaExit` added `e8 < e13` as onBar exit — score dropped 1.038 → 0.844 because it fires on bar open while still in trade. We wanted position-scoped trailing EMA evaluated at bar close inside `onPosition`, separate from entry gate semantics.

**Harmful onBar exit:**
```muse
when low <= lowest(low, 13) || e8 < e13: flat()   // score 0.844, kills WF trades
// wanted: onPosition { when close < ema(close, 13): flat() }
```

---

## 5. Composable risk-shell stmt-templates (runtime fix)

**Proposed signature:**
```muse
template DonchianVault(entry: Int, exit: Int, hardPct: Float, timeBars: Int) {
  onPosition {
    when bars_in_trade >= timeBars: flat()
    when unrealized_pnl < -hardPct * equity: flat()
  }
}
// usage: DonchianVault(21, 13, 0.05, 13)
```

**Why:** Every R4 strategy duplicates identical 6-line `onPosition` blocks. agent-06 notes stmt-template invocation throws `Cannot call null` in `gene-runner.js`. We inlined shells across s01–s05 and 21 probes — error-prone when tuning hard-stop from 5% → 3%.

**Duplicated five times:**
```muse
onPosition {
  when bars_in_trade >= 13: flat()
  when unrealized_pnl < -0.05 * equity: flat()
}
```

---

## 6. Probe batch runner / grid metadata

**Proposed signature:**
```muse
// harness flag, not language — included for completeness
python tournament_lab.py --grid agents/agent-02/_probe/*.ms --score
```

**Why:** Breaking the plateau required 21 hand-written `.ms` files and a custom Python scorer. A grid mode with automatic score + WF ranking would cut iteration from ~90s × 21 to a single command — critical when Fib window ladder has 10 valid lengths.

**What we built manually:**
```
_probe/p01..p21.ms + score_probes.py → found e8>e13 at score 1.038
```

---

# Agent 02 — MuseScript Wishlist (Round 5)

Features we wanted while grafting agent-06 cascade exits onto EMA 8/13 gates.

---

## 7. onBar vs onPosition exit deduplication

**Proposed signature:**
```muse
onPosition {
  when !exited_this_bar && falling(m.hist, 3): flat()
}
// or: exit_once_per_bar(exitRule)
```

**Why:** s05 adds five onPosition exit rules atop s03's rsiMacdExit onBar — eval shows **identical score** (1.469). Extra onPosition rules never fire because onBar cascade already flat'd. We wanted a way to express "only if onBar exit didn't trigger" or priority tiers without manual trade-path reasoning.

**Redundant stack (same score):**
```muse
onBar { when rsiMacdExit(): flat() }           // s03 — sufficient
onPosition { when falling(m.hist, 3): flat() } // s05 — no-op in practice
```

---

## 8. `falling()` / `rising()` on EMA outputs (still blocked)

**Status:** R4 wish #1 still open. R5 confirmed `falling(m.hist, 3)` works in `onPosition` but `falling(ema(close, 8), 2)` does not.

**Example we wanted for entry quality:**
```muse
when e8 > e13 && rising(e8, 2) && donchianHigh(21): long()
// rising(e8, 2) still blocked — static alignment only
```

---

## 9. Split exit-scope templates

**Proposed signatures:**
```muse
template onBarExit() -> Bool { ... }
template onPositionExit() -> Bool { ... }
// compiler warns if onBarExit rule duplicated in onPosition
```

**Why:** agent-06's `cascadeExit` mixes Donchian (bar-open sensitive) with EMA close checks. We copy-pasted into onBar only, but R5 s02 experiment showed moving MACD/falling to onPosition alone lifts WF (1.869 → 2.161) — no language hint about which predicates belong where.

**R5 split that worked (s02, WF 2.161):**
```muse
onBar { when donchianLow(13) || rsiOverbought(13, 72): flat() }
onPosition { when falling(m.hist, 3) && m.hist < 0: flat() }
// wanted: template scope annotation so we don't guess
```

---

## 10. Cascade tier ordering / belowEma sensitivity flag

**Proposed signature:**
```muse
template cascadeExit(tiers: List<ExitTier>) -> Bool
// ExitTier { kind: Donchian|Macd|Rsi|Ema, minBars: Int, eager: Bool }
```

**Why:** Dropping `belowEma(13)` from onBar cascade lifted score 1.413 → 1.469 (+0.056). The language gives no way to mark EMA exit as "onPosition-only after 5 bars" vs "onBar eager" — we discovered this by diffing s01 vs s03 manually.

**Score delta from one predicate:**
```muse
// s01 score 1.413 — includes belowEma(13) onBar
donchianLow(13) || macdBear(13,34,8) || rsiOverbought(13,72) || belowEma(13)

// s03 score 1.469 — same minus belowEma
donchianLow(13) || macdBear(13,34,8) || rsiOverbought(13,72)
```
