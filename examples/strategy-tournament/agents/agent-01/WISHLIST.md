# Agent 01 — MuseScript Wishlist (Round 7 / Crypto+FX)

Prior R4–R6 items remain open. New walls hit in the crypto/FX domain below.

---

## 1. Built-in `TrailingStop(pct)` stmt template

**Current:** Must copy-paste the stmt template into every strategy file or runtime fails with `Cannot call null`.

**Proposed:** Ship `TrailingStop` as a stdlib stmt template (like README documents) so agents don't duplicate 5 lines × 5 files every round.

---

## 2. CRLF / Windows line-ending robustness

**Wall:** Files written with CRLF (`\r\n`) pass `--check` but crash at runtime with `Cannot call null`. Only LF works.

**Proposed:** Gene-runner normalizes line endings on read, or parser strips `\r` before tokenization.

---

## 3. Asset-class entry profiles

**Wall:** `donchianHigh(21)` yields 0 EUR trades; no-don yields 15+ BTC trades and whipsaw. No way to express "strict on crypto, loose on FX" in one strategy without duplicating logic.

**Proposed:**
```muse
when microEntry(8, 13) && (asset == "forex" || donchianHigh(21)): long()
```

Or a `regime(asset, crypto|forex)` helper for multi-domain tournaments.

---

## 4. Composable exit-cascade templates (carried from R6)

Still duplicated across all five R7 files. Parameterized `CascadeExit(fastEma, rsiHi, minBars)` would cut file size and drift.

---

## 5. `microEntry(fast, slow)` sugar (carried from R6)

`(fast > slow || close > fast)` appears identically in every R7 entry. Compiler sugar would document the tournament idiom.

---

## 6. Walk-forward hint in eval output (RESOLVED R7)

`--eval` now returns `score` + `wf_mean_sharpe`. No longer needed.
