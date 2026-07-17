# Agent 01 — MuseScript Wishlist (Round 6 / FINAL)

Prior R4–R5 items remain open. Final-cycle language wishes below.

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

**Why:** Six rounds duplicated the same cascade block. R6 copied agent-05 templates verbatim into every file. One parameterized `cascadeExit` + `cascadePosition` pair would let agents vary only entry micro-cross geometry.

---

## 2. Entry latch for cross-then-confirm patterns

**Proposed signature:**
```muse
when armed_cross(fast, slow, confirm: high >= highest(high, 21), maxBars: 5): long()
```

**Why:** R6 winning move was manual OR-broaden `(fast > slow || close > fast)` to approximate champion's `close > e8` without abandoning cross identity. A first-class latch would replace this hack and preserve pure `crossover(fast, slow)` event entries.

---

## 3. `microEntry(fast, slow)` sugar for OR-broaden idiom

**Proposed:**
```muse
template microEntry(fast: Series, slow: Series) -> Bool {
  fast > slow || close > fast
}
```

**Why:** R6 probe p13 beat the champion by +0.006 using this exact boolean. It appeared in s01/s02 identically. Compiler sugar would document the tournament meta and prevent copy-paste drift.

---

## 4. Staged exit priority / first-match semantics

**Proposed:**
```muse
onPosition priority {
  first: when bars_in_trade >= 8 && unrealized_pnl > 0.03 * equity: flat("profit_lock")
  then:  when falling(m8.hist, 3): flat("momentum_fade")
}
```

**Why:** s01/s02/s03 produce identical 3m metrics — impossible to tell which exit tier fires. Tagged exits would clarify cascade pruning across future cycles.

---

## 5. Walk-forward hint in eval output

**Proposed:** `--eval` JSON includes `wf_mean_sharpe` and `score` alongside 3m metrics.

**Why:** R6 score gap vs champion was entirely WF (2.247 → 2.338). We built `_score.py` manually; one harness flag would have saved 30+ backtest runs during probing.
