# Agent 02 — MuseScript Wishlist (Round 7 / Crypto + FX)

Prior equity-cycle items remain in `LANGUAGE-WISHLIST.md`. Round-7 crypto+FX-specific wishes below.

---

## 1. Built-in `TrailingStop` prelude for gene-runner

**Problem:** `TrailingStop(0.05)` is documented as working through gene-runner, but the template must be **inlined in every strategy file**. Without it: `Cannot call null`. Agent-01 round-07 files are broken the same way.

**Proposed:** Gene-runner pre-expands a standard library:

```muse
template TrailingStop(pct: Scalar) {
  onPosition { when unrealized_pnl < -pct * equity: flat() }
}
```

**Why:** Six duplicate copies per round; one forgotten copy = zero-score run.

---

## 2. `emaTrendEntry(fast, slow)` compiler sugar

**Proposed:**

```muse
template emaTrendEntry(fast: Window, slow: Window) -> Bool {
  ema(close, fast) > ema(close, slow) || close > ema(close, fast)
}
```

**Why:** R7 probe p02→p03 jump (+0.41 score delta) came entirely from replacing crossover events with this OR-broaden idiom. Appears identically in all five agent-02 files. Documenting it as first-class sugar prevents drift from pure `crossover(ema(...), ema(...))` which fires zero trades under next-open on this window.

---

## 3. Adaptive trend gate by asset class

**Proposed:**

```muse
when trend_gate(crypto: 21, forex: 55): ...
```

**Why:** SMA(55) and dual SMA(55)&&SMA(89) gates produced **zero trades** on the entire Apr–Jul 2026 window. SMA(21) works for crypto but FX wanted slower gates. Asset-aware defaults would match BRIEF's 55/89 intent without manual per-domain tuning.

---

## 4. Exit-layer fire diagnostics (still open)

**Proposed:** `flat("trail")` tags + per-layer fire counts in `--eval` JSON.

**Why:** s01 (0.379) vs s05 (0.295) differ only in onPosition layers — identical trade counts on several symbols. Cannot tell whether EMA(13) trail or falling(spread) helped or hurt without tagged exits.

---

## 5. Shipped / resolved this cycle

| Feature | Status |
|---|---|
| `falling`/`rising` with `minBars` | **Used** — s01–s05 onPosition exits |
| Stmt-template expansion | **Used** — TrailingStop inlined per file |
| Composite `score` + `wf_mean_sharpe` in `--eval` | **Used** — all probing via crypto_fx_lab.py |
| Causal next-open execution | **Used** — mandatory for scoring |

---

## 6. Parameter sweep syntax (carry forward)

**Proposed:** `param gateLen = sweep(21, 34, 55)`

**Why:** R7 spent 8 probes finding SMA(21) beats SMA(55/89) on this window. One sweep line would replace manual file copies.
