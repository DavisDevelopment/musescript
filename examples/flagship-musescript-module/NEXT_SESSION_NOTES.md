# Notes for the next Claude — flagship ensemble thread, 2026-08-15

## ⚡ READ FIRST — v5 ablation is done. Latch did the work. Do not write v8.

Scored `flagship_ensemble_v5` **once** on heldout_v2 working folds (9×300, `next-open`, 10bps).
Sealed 2023–26 untouched. `gate_stats.VARIANTS` now includes v5 so `--report` sees it.

**2×2 (paired d_sharpe, n=2700):**

| cell | isolates | paired Δ | 95% CI | better |
|---|---|---|---|---|
| v5 vs v1 | **latch** (both have `rising(close,3)`) | **+0.237** | [+0.209, +0.266] | 1641/2700 |
| v4 vs v5 | **entry** (both have the latch; v4 dropped rising) | **+0.057** | [+0.040, +0.075] | 1441/2700 |
| v4 vs v1 | both changes (compound) | **+0.294** | [+0.263, +0.327] | 1716/2700 |

The two nested contrasts add: 0.237 + 0.057 = 0.294. **The latch is the main effect.** Restoring
rising does not kill v4's edge vs v1; dropping rising on top of the latch is a smaller, still
resolved increment. Mean trades/symbol from the same 10bps matrix: v1 12.13, v5 5.10, v4 5.61 —
the latch is what cuts turnover; v4 still beats v5 while trading *slightly more*, so the entry
increment is not a cost artifact vs v5.

v5 did **not** fail vs v1, so **do not** start hysteresis / `diag_regime_units.py` / a new genome.
No v6 (missing no-latch/no-rising cell) and no v8. Sealed set still sealed.

---

## Earlier — 2026-08-07 — broad8mo is superseded. Everything below it was judged on a broken instrument.

A multi-regime held-out set now exists (`results/HELDOUT_V2_REPORT.md`): **9 annual regime folds ×
300 symbols = 2700 symbol-folds**, 2014–2022, plus a **sealed** 2023→2026 set that is still sealed.
broad8mo (54 symbols, one 8-month up-window) was measured at **~7 effective independent bets** and
**could not resolve a single promote/reject decision** in this thread's history.

What changed when the same 13 variants were rescored properly:

- **116 of 117 cells are negative.** Every variant loses to buy-hold in every regime — including
  2022 (sustained bear) and 2020 (COVID crash). The much-cited **down/choppy edge did not
  replicate**; it was 13 trades across 4 symbols and it is gone.
- **v7b → v7h are identical to three decimals across all nine folds.** Seven rounds of tip/Done
  seal tuning, corpus 58% → 100%, bought **zero** measurable out-of-sample difference.
- **broad8mo's ordering was wrong in sign**, not merely unresolvable: it had ensemble_v1 beating
  v7h; here v7h edges v1 (+0.050). Both are economically negligible.
- **`flagship_ensemble_v4` is the best variant by a wide margin** — paired **+0.294**
  [+0.262, +0.327] vs ensemble_v1, and **+0.229 at ZERO cost**, so 78% of it is signal rather than
  its 5.6-trades/symbol turnover advantage. broad8mo rejected this variant at 4/54.
- **PBO over time = 0.02** (126 fold splits, median OOS rank 1/13) — ranking is stable across
  regimes. The test broad8mo structurally could not run.

**The single highest-value experiment now:** v4 changed TWO variables (latch + dropped
`rising(close,3)`). The controlled ablation — latch with `rising(close,3)` restored — run on
**heldout_v2, not broad8mo**. That tells you which half of the only real effect in this thread
actually does the work.

```powershell
python examples/flagship-musescript-module/harness/build_heldout_v2.py --sealed   # rebuild (seeded)
python examples/flagship-musescript-module/harness/heldout_v2.py --all-variants   # score
python examples/flagship-musescript-module/harness/heldout_v2.py --report         # inference
python examples/flagship-musescript-module/harness/gate_stats.py                  # broad8mo post-mortem
python examples/flagship-musescript-module/harness/diag_cost_confound.py          # turnover-vs-signal
```

⚠ **The sealed set (2023-01-28 → 2026-08, 101 symbols) is untouched.** It is strictly later in time
than every working fold. `heldout_v2.py` will not score it without `--unseal-final-answer`. Spend it
once, on one final candidate, and record the date and reason in the report.

⚠ **Survivorship bias** in heldout_v2 inflates buy-hold, so "everything is negative" is partly
artifact. Paired variant-vs-variant claims are unaffected and are the only ones the report makes.
Never quote an absolute return off it.

---

# Earlier the same day — diagnosis session (still valid)

## ✅ Done this session — v7h surfaced, v4's open question answered, no new variant written

Two things happened: the v7h gate failure was verified and written into the README, and attempt
#4's open question ("why did the chop sleeve break under the latch?") got a real answer. The
answer invalidates part of attempt #4's own writeup. Full detail:
`results/BROAD8MO_REPORT.md` → **"Diagnosis session (2026-08-07, later)"**.

## v7h: confirmed failing, README corrected

Re-ran the gate; reproduces the earlier numbers exactly:

```
flagship_v7h.ms: 10/54 (mean d_sharpe -0.999)   <- worst of the whole lineage
baseline (flagship_ensemble_v1.ms): 13/54 (-0.709)
GATE: REGRESSED (exit 1)
```

The README no longer presents v7h as "promote cleared" — there's a ⛔ box at the top stating the
gate failure and that `flagship_ensemble_v1.ms` is the best-generalizing artifact here. **v7h was
not reverted** (it's still the corpus champion, and its corpus numbers are real); only the claim
about what those numbers mean was corrected. Reverting is a human call.

## The v4 answer: it was a confound, not the latch

**v4 changed two things while reporting one.** Its trend-sleeve entry:

```
v1:  when trendRegime && position() == 0 && close > eTrend && rising(close, 3): long()
v4:  when position() == 0 && trendRegime: { sleeve.set(1); long() }
                                            ^-- rising(close, 3) silently dropped
```

That's v2's already-rejected "enter immediately on regime flip" folded in alongside the latch. The
chop sleeve's logic is byte-identical v1→v4 — so the break was never *in* the chop sleeve. The
trend sleeve simply enters ~2× as often and holds, and an open trend position locks the chop
sleeve out in both versions. Measured across all 54 tapes (trend sleeve simulated alone):

| Bucket | v1 entries/sym → v4 | v1 occupancy → v4 | ratio |
|---|---|---|---|
| strong_up | 3.8 → 6.2 | 36.3% → 45.7% | ×1.26 |
| mild | 3.6 → 6.2 | 26.1% → 36.5% | ×1.40 |
| **down_choppy** | **2.5 → 4.8** | **11.3% → 17.9%** | **×1.59** |

The bucket that broke takes the biggest hit. Session-notes hypothesis #2 (trend sleeve steals chop
entries) — **confirmed**. Hypothesis #1 (`sleeve.clear()` timing) — not needed to explain anything.
Hypothesis #3 (small sample) — **also confirmed, see below**.

**What this costs us:** attempt #4's headline ("the trend-sleeve half of the fix is validated") is
**not supported**. The strong_up gain could be the latch or the looser entry; they were never
separated. **The latch is still untested.**

## Two more findings worth knowing before you write anything

**1. The regime gate threshold is off by 100×.** MuseScript `roc()` returns *percentage points*
(`TradeBuiltins.hx:773-776` — `pctChange * 100`). Every ensemble file gates on
`rocTrend > trendRocMin` with `trendRocMin = 0.07`, commented as "7%" / "up >10%". The live gate
is **0.07%** — "up at all over 34 bars." So the "confirmed uptrend" sleeve runs 21% of bars in
names that ended the window *down* >5%.

**But do not assume fixing it helps** — the same measurement kills the obvious story. Tightening
to a true 7pp does **not** reduce the flicker attempt #4 diagnosed; it makes it relatively worse
(1-2 bar blips 33.1% → 46.1% of segments in strong_up). The flicker is the `close > eTrend`
conjunct crossing back and forth. A units fix is a correctness fix, not a flicker fix.

The main v5–v7 lineage is unaffected — it uses `roc` only in sign tests and against
empirically-tuned constants, both units-immune.

**2. The down_choppy edge is 13 trades.** v1's +0.213 is carried by four thin-traded names: CRM
(+1.374, 5 trades), COIN (+1.314, 2), ORCL (+1.203, 4), MCD (+0.822, 2). Everything else in the
bucket is negative. Treat "down_choppy broke / improved" claims — including v1's own +0.213 — as
n=13 results. That number should never have become a target.

## Reproducible diagnostics (new, in git — unlike the data)

```powershell
python examples/flagship-musescript-module/harness/diag_regime_units.py      # roc units + flicker structure
python examples/flagship-musescript-module/harness/diag_sleeve_occupancy.py  # v1-vs-v4 trend-sleeve occupancy
```

Both read the frozen tapes directly, run in seconds, need no gene-runner, and **consume zero
held-out degrees of freedom** — no backtest, no pass/fail read. This is the cheap mode of enquiry;
prefer it over writing a variant.

## The one experiment to run next — deliberately not run today

**v4's latch with v1's `rising(close, 3)` entry restored.** That is the single-variable test that
separates the latch from the confound, and it's now a diagnosed hypothesis rather than a guess.

It was not run today on purpose: four variants have already been scored against this one held-out
set in a single day, plus the v7h check. That is already more reads than the set can support
without becoming a tuning target itself — the exact mechanism that produced the v6l→v7h overfit.
**Run it first thing in a later session, once, and treat the outcome as one bit of evidence.**

If it passes, the latch is real and v1+latch is the candidate. If it fails, the latch is dead and
the flicker diagnosis — which is *structurally* true regardless — needs a different remedy
(hysteresis on the regime flag, e.g. requiring N consecutive in-regime bars to flip on and M to
flip off, is the obvious one and can be pre-screened with `diag_regime_units.py` before any
backtest).

## Standing discipline — unchanged, and it paid off today

Diagnose before writing the next variant. Today's session answered an open question with two
throwaway measurement scripts and **zero** gate runs against a new file; the previous three
attempts burned three gate runs to learn less. Run `heldout_gate.py` before calling anything a
promotion candidate — and note that v7h is proof the corpus/bulls/dBH bar does not substitute
for it.

## Gotcha: the held-out data is NOT committed

`tapes/broad8mo/*.csv`, `data/real/tape_broad8mo.csv`, `results/broad8mo_baseline.json` and
`results/BROAD8MO_REPORT.md` are all gitignored. Only code (`harness/*.py`, `strategies/*.ms`) is
in git. **All of it is still on disk as of this session** — read `results/BROAD8MO_REPORT.md`
before regenerating anything.

On a fresh clone, `heldout_gate.py` fails immediately with no data and no baseline. To rebuild:

```powershell
python examples/flagship-musescript-module/harness/heldout_gate.py strategies/flagship_ensemble_v1.ms --refresh-data
# then re-run v1 with --set-baseline once tapes/broad8mo/ exists again
```

`--refresh-data` pulls a NEW 8-month window ending today, **not** the frozen
2025-12-07..2026-08-06 window every number here is quoted against. Rebuilt numbers are not
comparable to anything in `BROAD8MO_REPORT.md`; only pass/fail-vs-rebuilt-baseline still works.

## Where the ensemble thread stands

- **`flagship_ensemble_v1.ms` — frozen baseline** (13/54, −0.709). Only ensemble variant that ever
  passed. Causal symbol-agnostic regime gate, plain donchian chop entry, no broadening.
- **v2, v3 — rejected**, same failure mode: broadening the chop sleeve's entries hurts, with or
  without v6l's fill-count throttle. *Conclusion, fairly confident: leave the chop sleeve at v1's
  level of complexity.*
- **v4 — rejected, and now known to be an uncontrolled two-variable change.** Kept as a data point
  about what NOT to conclude from it. Its flicker *diagnosis* is still sound; its *fix* is unproven.
