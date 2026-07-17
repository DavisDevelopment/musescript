# Agent 02 — MuseScript Wishlist (Round 6 — FINAL)

Accumulated from R4–R6. See `round-04/WISHLIST.md` and `round-05/WISHLIST.md` for full prior entries.

---

## 11. Parameterized `belowEma` trail tier in cascade templates

**Proposed signature:**
```muse
template cascadeExit(rsiHi: Scalar, emaTrail: Window, scope: ExitScope) -> Bool
// scope: onBar | onPosition(minBars: Int)
```

**Why:** R5 showed `belowEma(13)` onBar is too eager with `e8 > e13` gate (−0.056). R6 showed `belowEma(8)` onBar **wins the tournament** (+0.091 vs R5, +0.011 vs agent-05). The optimal trail EMA depends on entry gate semantics — no language hint that trail should match entry anchor (8) not alignment partner (13).

**R6 breakthrough (21 probes):**
```muse
// score 1.541 — belowEma(13), same as agent-05 except e8>e13 entry
belowEma(13)  // too slow to cut losers, hurts vs-BH

// score 1.560 — crown
belowEma(8)   // exits when price loses entry-anchor EMA
```

---

## 12. EMA alignment vs price-above-EMA entry helpers

**Proposed signatures:**
```muse
ema_aligned(fast: Int, slow: Int) -> Bool     // e8 > e13
price_above_ema(len: Int) -> Bool             // close > ema(close, len)
ema_entry_gate(mode: Align|Price|Both) -> Bool
```

**Why:** Agent-05 wins with `close > ema(8)`. We win with `e8 > e13`. Combining both (`close > e8 && e8 > e13`) scored **lower** (1.535). The language forces manual reasoning about which EMA predicate belongs on entry vs exit.

**Conflicting gates tested:**
```muse
when e8 > e13 && donchianHigh(21): long()              // R6 crown entry — 1.560
when close > e8 && e8 > e13 && donchianHigh(21): long() // stricter — 1.535
when close > e8 && donchianHigh(21): long()             // agent-05 — 1.549
```

---

## 13. Dual MACD fall3 scope (m8 vs m134)

**Proposed signature:**
```muse
falling(macd(close, fast, slow, sig).hist, bars: Int, scope: onBar|onPosition)
```

**Why:** Agent-05 uses `falling(m8.hist, 3)` in onPosition. R5 s02 used `falling(m.hist, 3)` (13,34,8) for WF lift. R6 s05 adding both **hurt** score (1.363). No way to express "fast MACD for exit, slow MACD for confirm" without duplicating rules and manual trade-path analysis.

**Harmful dual-fall stack:**
```muse
when falling(m8.hist, 3): flat()                              // agent-05 — works
when bars_in_trade >= 8 && falling(m.hist, 3) && m.hist < 0: flat()  // R6 s05 — drags to 1.363
```

---

## 14. RSI vault threshold as strategy param

**Proposed signature:**
```muse
rsiOverbought(len: Window, hi: Scalar = 75)  // or rsiVault(hi: 72|75|78)
```

**Why:** RSI 72 → 75 alone lifted agent-05 from 1.519 → 1.549. Confirmed in our R6 vault variants. We grid-searched 72 vs 75 manually; a single param sweep would have found this in one eval pass.

---

## 15. Probe grid runner (still manual)

**Status:** R4 wish #6 still open. R6 required 21 hand-written probe files under `round-06/_probe/` plus `score_probes.py`. Crown discovery (`belowEma(8)`) was probe p16 of 21.

**What we built manually:**
```
_probe/p01..p21.ms + score_probes.py → found belowEma(8) at score 1.560
```

---

## Open items from prior rounds (unchanged)

| # | Feature | Status |
|---|---|---|
| 1 | `rising()`/`falling()` on EMA series | Blocked |
| 2 | Cross-arm / delayed Donchian confirm | Blocked |
| 3 | Tiered EMA alignment helper | Workaround: inline e8/e13 |
| 4 | Trailing EMA stop scope clarity | Workaround: onPosition `close < fast` |
| 5 | Composable risk-shell stmt-templates | `Cannot call null` in gene-runner |
| 6 | Probe batch runner | Manual Python scripts |
| 7 | onBar vs onPosition exit deduplication | Manual trade-path reasoning |
| 8 | falling/rising on EMA outputs | Blocked |
| 9 | Split exit-scope templates | Manual; R6 s03 WF 2.44 proves value |
| 10 | Cascade tier ordering / belowEma sensitivity | **R6 resolved empirically: use ema(8)** |
