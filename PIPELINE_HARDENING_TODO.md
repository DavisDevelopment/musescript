# Pipeline Hardening & Anti-False-Positive Pass — Cursor TODO

**Date:** 2026-07-28
**Trigger:** We discovered the fitness/OOS scorer is **gamed by thin-trade genomes** — a strategy that
makes 1 lucky trade earns a high Sharpe, "holds" OOS on that single trade, and wins selection. Nearly
every "pulse" this arc (EW-Donchian, regime tight_spread, auction diag) carries that 1–2 trade
signature. **Our measuring instrument manufactures false positives.** Until that is closed, no result
is trustworthy.

**Mission:** an evaluate → harden → stress-test pass over **every** component in the forecast/
co-evolution/benchmark pipeline, with special weight on (a) **theoretical robustness** and (b)
**hardening the measurement so a false positive is nearly impossible.**

---

## Ground rules (read first)

- **The North-Star test:** two *controls* (Bucket J) must both pass before ANY component is called
  "hardened": a pure-noise forecaster the pipeline MUST reject, and a planted real edge the pipeline
  MUST detect. If either fails, the instrument is broken — fix that before trusting anything else.
- **Every fix ships with a test that FAILS on the pre-fix code** (a real regression guard, not a
  smoke test). Prefer property/invariant tests over example tests.
- **Determinism is non-negotiable:** anything with randomness uses `DetRng`/`DetMath`. New randomness
  must be provably byte-identical across JVM + node (extend `DetParityDump`).
- **Report NO-GOs as loudly as GOs** (ledger discipline). A hardening task that finds a component is
  fine still gets logged as "audited, clean."
- **Boundaries:** Cursor owns this whole pass. Claude stays OUT of the files under active hardening to
  avoid collision — coordinate before touching `Fitness`, `Variation`, `ProjectionProvider`,
  `CorpusEvoRun`, `EwBenchmark*`. Work bucket-by-bucket; commit per bucket with the bucket id.
- **Priorities:** P0 = blocks trusting any result (do first). P1 = correctness of a tested component.
  P2 = robustness depth. Do all P0 before any P1.

---

## Bucket A — THE MEASUREMENT INSTRUMENT (P0 — this is where the leak lives)

Files: `evo/Fitness.hx`, `evo/FitnessResult.hx`, `evo/graal/CorpusEvoRun.hx` (OOS re-score +
`[ew-host OOS]`), `evo/ProjectionScore.hx`, `evo/MapElites.hx`.

- [ ] **A1. Minimum-trade-count gate.** A genome's Sharpe/fitness is INELIGIBLE (treated as NEG_INF
  or heavily penalized) below `minTrades` (default ≥20, configurable). Applies to IS fitness AND the
  OOS re-score AND `[ew-host OOS]`. *Accept:* a 1-trade genome can never rank in the top-K or be
  reported as "HELD/BEATS". Add a test with a hand-built 1-trade genome that must score NEG_INF.
- [ ] **A2. Deflated / Probabilistic Sharpe Ratio (DSR/PSR).** Replace raw Sharpe in ranking + OOS
  verdict with a sample-size-aware score that discounts Sharpe achieved on few observations and
  corrects for skew/kurtosis (Bailey & López de Prado). *Accept:* two genomes with equal Sharpe but
  10× different trade counts rank the higher-N one strictly above; unit test the PSR formula against
  known values.
- [ ] **A3. Multiple-testing awareness.** We run many seeds × configs × instruments × host-kinds.
  Track the number of trials and deflate the significance threshold accordingly (DSR trials term, or
  Bonferroni/BH on reported p-values). *Accept:* the `[ew-host OOS]` verdict states the effective
  number of trials and a corrected threshold, and a result only prints "BEATS" if it clears it.
- [ ] **A4. Block-bootstrap confidence intervals.** Returns are autocorrelated → i.i.d. bootstrap
  understates variance. Add stationary/block bootstrap for Sharpe/return CIs; a "beat" must have a CI
  that excludes the null, not just a point estimate above it. *Accept:* CLI prints `[lo, hi]` and the
  verdict uses CI, not point.
- [ ] **A5. OOS re-score honesty.** Audit `printRealHoldout` / `[ew-host OOS]`: it must (i) apply the
  min-trade gate, (ii) use DSR, (iii) not let elitism duplicate the same genome into the "top 10"
  (dedup by structural key — verify it actually does), (iv) report trade counts inline. *Accept:*
  re-run the auction TSLA case; the 1-trade "beats" must now read NO-GO.
- [ ] **A6. `ProjectionScore` metric audit.** `rankIC`/`directionalAccuracy`/`hitRate`/`bandCoverage`
  — verify tie-handling, min-sample floors (already `< 3 → 0`; raise + justify), NaN propagation, and
  that a constant predictor scores 0 not spuriously high. Property tests: permutation null of each
  metric centers on 0.

## Bucket B — STATISTICAL RIGOR / ANTI-FALSE-POSITIVE (P0 — theoretical robustness)

New: `evo/rigor/` (Cursor's) — pure, unit-tested statistics.

- [ ] **B1. PBO (Probability of Backtest Overfitting).** Implement combinatorially-symmetric
  cross-validation (CSCV, Bailey et al.): does the IS-best strategy stay above-median OOS? Report PBO
  for every evolution run. *Accept:* PBO on a random-forecaster population is ≈0.5; PBO gate flags
  overfit selection.
- [ ] **B2. Purge & embargo around the IS/OOS split.** Any strategy/host whose warmup window or
  indicator lookback reaches across the split must be purged; add an embargo gap of `maxLookback`
  bars. *Accept:* a strategy with a 200-bar indicator can't be scored on OOS bars within 200 of the
  split; test that the boundary is enforced.
- [ ] **B3. Minimum-effect-size + pre-registration harness.** A helper that takes (hypothesis, null,
  threshold, horizon) BEFORE a run and records it, then evaluates against it — so no post-hoc
  threshold shopping. *Accept:* verdicts reference the pre-registered threshold.
- [ ] **B4. Seed-robustness aggregator.** No result stands on one seed. A helper that runs N seeds and
  reports the DISTRIBUTION of the verdict metric; a "GO" requires the median (not max) to clear the
  bar. *Accept:* re-run a prior "pulse" across 20 seeds; show the max-seed cherry-pick vs the median.
- [ ] **B5. Universe-robustness.** A "GO" must hold across an instrument universe, not a cherry-picked
  name. Wire a multi-tape aggregate verdict. *Accept:* TSLA-only "edge" is flagged as single-name.

## Bucket C — LEAKAGE & PIT DISCIPLINE (P0)

- [ ] **C1. Host causality audit.** For EVERY host (`Lattice`, `Mcmc`, `Regime`, `Auction`): assert
  `cloudAt(t)` is a pure function of bars ≤ t. Build a **leakage probe**: run the host on a tape, then
  again on the tape with all bars > t scrambled; `cloudAt(t)` MUST be byte-identical. Any divergence =
  a leak. *Accept:* probe passes for all four hosts; wire it as a standing test per host.
- [ ] **C2. Benchmark target boundaries.** Audit `realizedTarget`/`realizedVol`/`forwardRange` in
  `ProjectionScore` + all `*BenchmarkCli`: the predictor uses ≤ t, the target uses > t, and the last
  `H` bars are excluded. *Accept:* an off-by-one that lets `t` see `t` fails a test.
- [ ] **C3. `decorateBars` / `materialize` causality.** Verify the host-column decoration streams
  strictly causally (onBar then cloudAt, never preloading a future column). *Accept:* a decorated
  column at bar t equals the streaming host's `cloudAt(t)` field exactly.
- [ ] **C4. Warmup honesty.** Confirm anchors/evals never start before enough history; document each
  runner's warmup and test the guard.

## Bucket D — DETERMINISM & RNG QUALITY (P1)

Files: `ew/mcmc/DetRng.hx`, `DetMath.hx`, `DetParityDump.hx`.

- [ ] **D1. RNG statistical battery.** Given the past `Rand.int` low-bit bug, subject `DetRng` to
  SERIAL tests (not just marginals): lag-k autocorrelation of `next()`/`nextUnit()`, chi-square
  uniformity of `nextInt(n)` for even AND odd n, gap test, and a spectral/bit-plane check. `nextInt`
  must have no modulo bias. *Accept:* all tests pass; document the suite.
- [ ] **D2. Gaussian quality.** `nextGaussian` (Marsaglia polar): mean≈0, var≈1, no serial
  correlation, Anderson-Darling normality on a large sample. *Accept:* passes; the caching (haveGauss)
  doesn't introduce lag-1 correlation.
- [ ] **D3. DetMath accuracy + edge cases.** `exp`/`log` max relative error vs a high-precision
  reference across a wide domain; behavior at subnormals, 0, negative, inf, NaN, huge/tiny. *Accept:*
  documented error bound (< 1e-10 rel over the used domain) + edge cases return sane values.
- [ ] **D4. Extend the parity gate.** `DetParityDump` must diff byte-identical across JVM+node for the
  REGIME chain (already added), AND for any new randomized component (Bucket B bootstrap, host
  predictive sampling). *Accept:* `diff` empty for every randomized path.

## Bucket E — FORECAST SUBSTRATES (P1 — per-host correctness + theory)

- [ ] **E1. RegimeMcmc convergence & mixing.** Add diagnostics: acceptance rate in a healthy band,
  effective sample size, trace stationarity, and R-hat across independent chains. Verify the σ-ascending
  identifiability gate can't be violated; prior-sensitivity sweep on `persist`. *Accept:* documented
  ESS/R-hat on the recovery test; a too-short budget is flagged, not silently wrong.
- [ ] **E2. RegimeMcmc calibration.** Is the predictive band calibrated? Coverage of the p05–p95
  predictive interval should be ≈90% on synthetic data with KNOWN generating process. *Accept:*
  coverage test within tolerance.
- [ ] **E3. Auction / VolumeProfile audit.** Value-area computation correctness (contains exactly p%
  of volume around POC), volume=0 / degenerate-profile handling, binning-count sensitivity, and
  justify or LEARN the hand-tuned `softMasses` constants (0.55/0.35/…) instead of magic numbers.
  *Accept:* value-area invariant test; a sensitivity table over bins; constants documented/sourced.
- [ ] **E4. EW rule completeness.** Adversarial pivots (ties, zero-length legs, collinear, NaN),
  and a check that the hard rules match Frost & Prechter exactly (no soft float in a boolean gate —
  re-verify). *Accept:* fuzz test over degenerate pivot sets never crashes / never mis-gates.
- [ ] **E5. ForecastCloud invariants.** For all hosts: `priceLo ≤ priceMid ≤ priceHi`, `probUp∈[0,1]`,
  `topMass∈[0,1]`, `entropy≥0`, `samples≥0`, NaN only where semantically "N/A". *Accept:* one shared
  invariant test parameterized over every host.

## Bucket F — CO-EVOLUTION MACHINERY (P1)

Files: `evo/Variation.hx`, `Simplify.hx`, `ProjectionProvider.hx`, `CorpusSeed.hx`, `Expand.hx`,
`evo/nma/NmaNodeEvalPool.hx`, `Canonical.hx`.

- [ ] **F1. Struct-rebuild field-drop audit (the drain-bug class).** We already found TWO rebuilders
  that dropped `projections` (`compactParams`, `Simplify`). EXHAUSTIVELY audit every place that
  reconstructs a `StrategyGenome` struct literal (grep `entryLong:`) and every `ProjectionDecl`/NMA
  rebuild for silently-dropped fields. *Accept:* a property test that round-trips a fully-populated
  genome through every public Variation/Simplify/NMA op and asserts NO field is lost.
- [ ] **F2. NmaNodeEvalPool JSON-serialization leak.** The multi-worker path drops `projections`
  (enum+Map can't `JSON.stringify` round-trip) — currently masked by `--ew-host` forcing threads=1.
  Either fix the serialization or hard-guard it so a host genome can NEVER be silently scored without
  its projection. *Accept:* a test that a host genome through the worker path either round-trips
  intact or is explicitly rejected — never silently stripped.
- [ ] **F3. ProjectionProvider binding/caching correctness.** `bindHostForGenome` cache-key must not
  collide across different decls/tapes; `materialize` must recompute when bars change; auto-bind must
  stay PIT. *Accept:* cache-collision test; a tape swap invalidates clouds.
- [ ] **F4. Reinject / drain guard.** With the drain fixed, reinject should be idle on a normal run.
  Add a test/telemetry assertion that reinject fires ~0× when host genomes are healthy; if it fires,
  that's a signal something still drains. *Accept:* long run logs reinject count ≈ 0.
- [ ] **F5. Seed integrity.** `seedFromEwHostProjection` for every kind (lattice/mcmc/regime/auction)
  produces genomes whose SProj reads reference fields the host actually emits (e.g. regime/auction
  `inv` is NaN — the `vs_invalidate` seed is dead weight; either fix or drop per-kind). *Accept:*
  per-kind seed validity test.

## Bucket G — BACKTEST & COST ACCOUNTING (P1)

Files: `harness/OrderSim.hx`, `BacktestEngine.hx`, `HarnessContext.hx`, `Fitness.evaluate`.

- [ ] **G1. Cost model honesty (turnover).** Re-verify against the known turnover-undercharge bug:
  every position change is charged `costBps` on the traded notional, both entry and exit, including
  flips. *Accept:* a hand-computed 3-trade scenario matches the engine's charged cost to the cent.
- [ ] **G2. Sizing semantics.** The `netRet%` unit-sizing issue (buy-hold showed +0.3% on a +66% move)
  — make position sizing capital-relative or clearly document units so profit numbers are comparable.
  *Accept:* buy-hold net return ≈ the tape's actual move; a test pins it.
- [ ] **G3. Fill realism.** No same-bar look-ahead in fills (`fillNextOpen` honesty), slippage
  assumptions documented. *Accept:* a strategy can't fill at a price its signal bar couldn't see.
- [ ] **G4. Bankruptcy/equity-floor.** Edge behavior (equity → 0, negative) doesn't produce nonsense
  Sharpe. *Accept:* a blown-up equity curve scores NEG_INF, not a lucky ratio.

## Bucket H — DATA INTEGRITY (P2)

Files: `harness/OhlcvCsv.hx`, the tapes.

- [ ] **H1. Tape sanity.** Every tape: monotone timestamps, no gaps/dupes, OHLC consistency
  (low≤open/close≤high), volume≥0, no zero/negative prices, split/dividend adjustment consistency.
  *Accept:* a tape-linter that must pass on every `data/real/*` and `corpus/tapes/*`.
- [ ] **H2. Look-ahead in data.** Confirm no adjusted-close survivorship/look-ahead artifacts;
  document the adjustment method. *Accept:* documented; spot-check a known split date.
- [ ] **H3. Realized-vol / realized-target computation.** Shared, tested implementation (not
  re-derived per CLI) so every benchmark computes the target identically. *Accept:* one canonical
  `RealizedTargets` module all runners import.

## Bucket I — BENCHMARK RUNNERS (P1)

Files: `ew/EwBenchmark.hx`, `EwBenchmarkCli.hx`, `EwProfitCli.hx`, `RegimeBenchmarkCli.hx`,
`AuctionBenchmarkCli.hx`.

- [ ] **I1. Null-baseline strength audit.** Each runner's null must be the STRONGEST cheap baseline,
  not a strawman: capture→±1ATR (done), vol→persistence (done), direction→drift (done) — verify each
  is actually hard, and add a random/shuffled null everywhere. *Accept:* documented null per metric.
- [ ] **I2. Metric-gaming audit.** For each runner, ask "what degenerate strategy maxes this metric?"
  (e.g. trade-once, predict-constant, predict-yesterday). Add a guard/penalty. *Accept:* each
  degenerate strategy scores at/below null.
- [ ] **I3. Shared harness.** The four runners duplicate anchor-grid/warmup/loadBars logic — factor
  into one tested harness so a fix lands everywhere. *Accept:* one `BenchmarkHarness`, runners are thin.

## Bucket J — META CONTROLS (P0 — the tests-of-the-tests; do these FIRST and LAST)

These make false positives nearly impossible by validating the instrument itself.

- [ ] **J1. NEGATIVE CONTROL (must FAIL).** A pure-noise forecast host (`NullForecastHost` emitting
  random/shuffled clouds via `DetRng`) and a coin-flip trader. Run them through the ENTIRE pipeline —
  benchmark + evolution + OOS re-score. **The pipeline MUST report NO-GO / no edge for them.** If a
  noise forecaster EVER "beats buy-hold OOS" or scores skill, the instrument is leaking — that's a P0
  bug. *Accept:* noise control returns NO-GO across all runners and evolution, across many seeds.
- [ ] **J2. POSITIVE CONTROL (must PASS).** A planted, known-real edge (a host that peeks a SMALL,
  bounded, noisy amount at the future target — a synthetic oracle with tunable signal strength). The
  pipeline MUST detect it, and detection strength must scale monotonically with planted signal.
  *Accept:* at signal=0 → NO-GO (== J1); as signal↑ → GO, monotonically. This proves the pipeline can
  find edge when it truly exists (guards against a pipeline so strict it rejects everything).
- [ ] **J3. Label-shuffle test.** Shuffle the realized targets (break the time link) and re-run every
  benchmark: all skill/IC must collapse to ≈0. *Accept:* shuffled IC ~0 everywhere; nonzero = leak.
- [ ] **J4. Standing CI gate.** J1+J3 become a required test that runs on every change. A commit that
  makes the noise/shuffle controls "pass" (i.e. show fake edge) is a build failure. *Accept:* wired
  into the test main; red on any instrument leak.

---

## Suggested order
J1 + J3 (build the negative controls FIRST — they'll immediately expose the thin-trade leak and any
others) → Bucket A (fix the leak) → J2 (confirm we can still detect real edge) → Bucket C (leakage) →
Bucket B (rigor) → then P1 buckets D–I in any order → re-run J1/J2/J3 at the end.

**Definition of done for the whole pass:** J1 rejects noise, J2 detects planted edge scaling with
strength, J3 collapses under shuffle, and re-running the auction/EW/regime comparisons through the
hardened instrument reproduces the honest NO-GOs (no resurrected false pulses). Only THEN is a future
"GO" believable.
