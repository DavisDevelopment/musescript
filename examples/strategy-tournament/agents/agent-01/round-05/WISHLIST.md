# Agent 01 — MuseScript Wishlist (Round 5)

New language feature requests surfaced while building R5 CascadeCrown + micro-cross hybrids.
Prior R4 items remain open; only **new** requests listed below.

---

## 1. Composable exit-cascade templates

**Proposed signature:**
```muse
template CascadeCrown(fastEma: Window, anchorEma: Window, macdFast: Window, macdSlow: Window, macdSig: Window) {
  m = macd(close, macdFast, macdSlow, macdSig)
  onPosition {
    when unrealized_pnl < -0.05 * equity: flat()
    when bars_in_trade >= 13: flat()
    when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat()
    when bars_in_trade >= 5 && close < ema(close, fastEma): flat()
    when bars_in_trade >= 8 && close < ema(close, anchorEma) && m.hist < 0: flat()
    when falling(m.hist, 3): flat()
    when rsi(close, 13) > 72: flat()
  }
}
```

**Why:** Five R5 strategies duplicate the same 7-line `onPosition` block from agent-06. A single parameterized cascade template would let us vary only the entry micro-cross while keeping the proven exit shell DRY.

---

## 2. Entry latch for cross-then-confirm patterns

**Proposed signature:**
```muse
when armed_cross(fast, slow, confirm: high >= highest(high, 21), maxBars: 5): long()
```

**Why:** `crossover(ema8, ema34) && donchianHigh(21)` fires on ≤2 bars per 63-bar tape (s02/s03). We want: arm on cross, enter on first Donchian confirm within N bars, disarm on crossunder — preserving crossover identity without starving trade count.

**Example gap:**
```muse
// s03: 2 SPY trades despite +0.33 mean d-Sharpe
when crossover(fast, slow) && high >= highest(high, 21): long()
```

---

## 3. `sma` / `ema` parity in `crossover` diagnostics

**Proposed:** Compiler warning when `crossover(fast, slow)` produces < N trades on a tape, suggesting level-gate fallback.

**Why:** R5 s02 (crossover 8/13) and s03 (crossover 8/34) are statistically starved on 3m tapes. We manually A/B level vs cross; a trade-count diagnostic at compile or eval time would speed iteration.

---

## 4. Staged exit priority / first-match semantics

**Proposed:**
```muse
onPosition priority {
  first: when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat("profit_lock")
  then:  when falling(m.hist, 3): flat("momentum_fade")
}
```

**Why:** s01/s03/s04/s05 produce identical SPY metrics — redundant exit clauses make it impossible to tell which rule actually closed a trade. Tagged exits would clarify which cascade tier fires and guide pruning.
