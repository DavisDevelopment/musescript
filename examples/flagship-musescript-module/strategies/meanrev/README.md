# Mean-reversion strategy library — 28 strategies, ground-truthed, 2026-08-07

Honest status: **none of these are flagship-grade robust yet.** `flagship_v7e` sits at corpus
70.0% (42/60) after 7 major versions and dozens of probe/sleeve iterations. These are first-pass,
untuned designs, evaluated once each — the best of them (`rolling_zscore_vol_norm.ms`, 48.3%) is a
genuinely promising *starting point* for the same iteration process the flagship lineage went
through, not a finished, promotable strategy. Calling any of these "robust" without that iteration
would be exactly the overclaim this whole harness exists to catch.

## What "unique" means here

28 genuinely distinct mean-reversion *mechanisms* — different signal families (RSI, Stochastic,
Williams %R, hand-built CCI, Bollinger/Keltner/Donchian bands, VWAP, z-score, percentile-rank,
gap-fade, wick-exhaustion, volume-capitulation, regime-gated), not 28 parameter reskins of one
idea. Full list and one-line mechanism description in each file's header comment.

## Method

Every strategy was run through the project's real harness against real market tapes — not written
and assumed good:
- All 28: `score_probe.py` (10 liquid symbols × 2 windows, 20 backtests each vs. buy-hold).
- Top 9 by that pass rate: `corpus_score.py` (15 symbols × 4 windows, 60 backtests each).
- Pass bar (unchanged from the harness's own criteria, not loosened for this batch):
  `trades >= 1 and sharpe > 0 and sharpe > buy-hold sharpe and max_drawdown <= 0.25`.

Three real bugs found and fixed in the process, not glossed over:
- `hl2()`/`hlc3()`/`ohlc4()` threw `TypeError: Cannot read properties of null (reading 'apply')`
  at runtime — **FIXED at the engine level, 2026-08-07**, not just worked around. Root cause: both
  `MuseParser.hx` (class-body syntax) and `StrategyParser.hx` (`strategy {}` block syntax, what
  every file in this folder uses) lower a bare identifier through an `isBarField()` check — correct
  for the common case (`hlc3` with no parens, meaning "this bar's value," same as `close`/`high`) —
  but neither checked whether the identifier was actually in CALL position first. So `hlc3()`
  parsed as `Call(BarField("hlc3"), [])`: invoking a resolved Float as if it were a function.
  `vwap()` never had this bug because `vwap` is registered ONLY as a callable, never as a bar-field
  identifier. Fixed by peeking for a following `(` before committing to the bar-field
  interpretation in both parsers (`StrategyParser.hx`'s primary-expression parser, `MuseParser.hx`'s
  `ECall` lowering — the latter needed manual position-restamping on the callee to avoid regressing
  a strict-mode diagnostic test, caught by the existing suite before considering this done).
  Full engine test suite: **78,669/78,669 assertions pass** post-fix (was 78,668/78,669 on the
  first attempt — the position-stamping regression above). `cci_style.ms` still builds typical
  price by hand rather than switching back to `hlc3()`/`(high+low+close)/3.0` being equivalent now
  either works; left as-is since it was already correct and re-touching it isn't worth the risk.
  - **This was blocking a live product surface, not just this batch**: `mobile/src`'s MuseScript
    editor/autocomplete surfaces all three functions as valid (they type-check), so any user who
    reached for `hl2()`/`hlc3()`/`ohlc4()` in Studio or Blueprints hit this exact runtime crash
    with no warning it was ever going to fail. Fixed upstream now, not just documented — the next
    `gene-runner.js` rebuild any consumer picks up (mobile's own bundled runtime is a separate
    build; this fix lands there whenever that gets synced/rebuilt from current `muse-script`
    source, not automatically).
- Two strategies (`bb_squeeze_release`, `macd_hist_extreme`) initially had thresholds so strict
  they produced **zero trades across all 20 backtest cells** — not a "this doesn't work" result,
  a "this never even tries" result. One honest recalibration pass each (loosened the compression
  ratio and the ATR-normalized histogram threshold); re-tested; both now trade but still perform
  poorly (see table). Left as-is rather than iterating further — tuning a strategy's parameters
  until it passes a probe you also control is p-hacking, even at small scale.

## Corpus scoreboard (15 symbols × 4 windows = 60 cells, real backtests, causal next-open, 10bps)

| Strategy | liquid10 eval_3m | liquid10 wf_2022q1 | CORPUS | Verdict |
|---|---|---|---|---|
| **rolling_zscore_vol_norm.ms** | 8/10 | 8/10 | **29/60 (48.3%)** | Strongest candidate — most consistent across all 4 windows, not just the 2 easy ones. |
| turtle_soup_false_break.ms | 8/10 | 4/10 | 28/60 (46.7%) | Strong on eval_3m, weak on wf_2022q1 — window-dependent, not all-weather yet. |
| stoch_oversold.ms | 2/10 | 9/10 | 26/60 (43.3%) | Lopsided: near-dead on eval_3m, strong on wf_2022q1. |
| atr_band_reversion.ms | 3/10 | **10/10** | 25/60 (41.7%) | Perfect on one window, weak on the other — a real regime-dependence, not noise. |
| cci_style.ms | 5/10 | 6/10 | 22/60 (36.7%) | Middling everywhere; the most "average" of the batch. |
| percent_rank_reversion.ms | 4/10 | 9/10 | 20/60 (33.3%) | 0/15 on wf_2024q4 — fails outright in that window. |
| rsi14_neutral.ms | 3/10 | 9/10 | 19/60 (31.7%) | Also 0/15 on wf_2024q4. |
| zscore_sma20.ms | 3/10 | 9/10 | 19/60 (31.7%) | Also 0/15 on wf_2024q4 — same weak spot as rsi14_neutral. |
| bb_percentb.ms | 3/10 | 9/10 | 19/60 (31.7%) | Near-identical numbers to zscore_sma20 — the two mechanisms are converging on the same trades more than "unique" implies; worth a correlation check before trusting them as diversifying. |

The other 19 strategies only ran the 2-window quick probe (`score_probe.py`), not the full 60-cell
corpus — their `eval_3m`/`wf_2022q1` numbers are in the harness logs (not reproduced here to keep
this table honest about what was actually deep-tested vs. quick-screened). Weakest of the quick-
screened group: `rsi2_connors` (0/10, 3/10), `bb_squeeze_release` (0/10, 2/10 after recalibration),
`macd_hist_extreme` (1/10, 0/10 after recalibration), `volume_spike_reversion` (1/10, 1/10),
`wick_exhaustion` (3/10, 1/10), `rsi_divergence_lite` (0/10, 1/10) — none of these look viable as
configured; they'd need real rework, not just a threshold nudge, to be worth a corpus run.

## Honest limits of this pass

- **The corpus-score batch previously took ~15 minutes of pure Node-process-spawn
  overhead** for 9 strategies (see repo-root `CURSOR_BATCH_RUNNER_SPEC.md`). Phase 1
  warm batch-runner is now landed in the harness — rebuild with `haxe build-batch.hxml`
  and see [`harness/BATCH_RUNNER.md`](../../harness/BATCH_RUNNER.md). Re-timing the
  top-9 corpus under warm batch is on the remaining checklist there.
- **Single-seed, single-run per strategy** — no seed-robustness sweep, no walk-forward promotion
  gate applied (the flagship lineage's `promote()` criteria were never run against these).
- **No cost/frequency sensitivity check** — all runs at a fixed 10bps; nobody here knows yet how
  fast the edge decays at 20bps or how these behave under `--matrix`'s honesty/frequency axes.
- **No bull-market subset check** (`bull_score.py`) — flagship's own scoreboard treats this as a
  separate, important axis (its bulls-only pass rate is materially different from its overall
  corpus number); these strategies haven't been checked against it at all.

## Suggested next step, if this becomes a real workstream

Take `rolling_zscore_vol_norm.ms` through the same probe/sleeve iteration process visible in
`../flagship_v0.ms` → `../flagship_v7e.ms`'s history — it's the only one of the 28 that's
consistent across windows rather than lopsided, which is what actually made prior iterations here
promotable. Everything else in this set is better read as a mechanism-diversity survey (which
signal families are even worth iterating on) than as finished candidates.
