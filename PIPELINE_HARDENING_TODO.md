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

**Progress (2026-07-28 evening — firming pass):** Soft spots from the critical audit closed where
feasible. J2 e2e standing test green; live PBO / elite-median / universe prints on CorpusEvoRun OOS;
IS `rankScoreFacts` default; `--n-trials` default 50; TapeLinter on primary loads; GitHub Actions
workflow added. Multi-CLI-seed restarts and full CorpusEvoRun host co-evo on long tapes remain soft
(bounded CLI re-runs document honest NO-GOs).

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

- [x] **A1. Minimum-trade-count gate.** `Fitness.defaultMinTrades=20`; `score`/`scoreFacts`/`robustScore`
  resolve null → default. CorpusEvoRun `--min-trades` wires IS + OOS. Test: `testOneTradeGenomeScoresNegInf`.
- [x] **A2. Deflated / Probabilistic Sharpe Ratio (DSR/PSR).** `evo/rigor/ProbSharpe.hx` + `Fitness.rankScore`
  / `rankScoreFacts`. Equal-Sharpe / higher-N ranks above; DSR deflates under trials.
  **IS selection:** CorpusEvoRun `scoreOf` defaults to `rankScoreFacts` (DSR when `--n-trials`>1);
  `--no-rank-dsr` restores raw Sharpe. Tests in `TestPipelineHardening`.
- [x] **A3. Multiple-testing awareness.** `--n-trials` **default 50** (was 1 — silent no-deflation).
  `--n-trials 1` without `--prereg` prints WARNING. `OosVerdict` BEATS only if DSR clears gate.
  Wired into `[ew-host OOS]` + IS rank.
- [x] **A4. Block-bootstrap confidence intervals.** `evo/rigor/BlockBootstrap.hx`; OOS verdict requires
  CI excluding 0; CLI prints `[lo, hi]`.
- [x] **A5. OOS re-score honesty.** `printRealHoldout` applies min-trade gate, DSR+CI+trials, structural
  dedup (already present), trade counts inline. Thin-trade → NO-GO via `OosVerdict`. Equity curves
  always materialized (`Fitness.equityCurveNeeded=true`) so DSR/CI/PBO see real returns.
- [x] **A6. `ProjectionScore` metric audit.** `minSample` raised 3→10 (justified); constant predictor → 0;
  below-floor → 0. Tests added.

## Bucket B — STATISTICAL RIGOR / ANTI-FALSE-POSITIVE (P0 — theoretical robustness)

New: `evo/rigor/` — pure, unit-tested statistics.

- [x] **B1. PBO (Probability of Backtest Overfitting).** `evo/rigor/Pbo.hx` (CSCV). Random pop ≈0.5 tested.
  **Live:** CorpusEvoRun `printRealHoldout` prints `[rigor PBO]` over top-K OOS 4-window slices
  (skips honestly when <2 strategies).
- [x] **B2. Purge & embargo around the IS/OOS split.** `evo/rigor/PurgeEmbargo.hx` + tests. CorpusEvoRun
  already had `--embargo`; helper documents / enforces lookback-aware legality.
- [x] **B3. Minimum-effect-size + pre-registration harness.** `evo/rigor/PreRegistration.hx` + tests.
  CorpusEvoRun `--prereg` acknowledges multi-testing when `--n-trials 1`. Full sealed-threshold
  enforcement against champion metric still library-thin (helper + flag; not a hard abort gate).
- [x] **B4. Seed-robustness aggregator.** `evo/rigor/SeedRobustness.hx` — GO requires median, not max.
  **Live:** CorpusEvoRun prints `[rigor seed-median]` over top-K OOS Sharpes; `AuctionHardenedOosCli`
  medians across host seeds. **Still soft:** true multi-`--seed` CLI restart aggregator not wired
  (would need an outer loop / job matrix).
- [x] **B5. Universe-robustness.** `evo/rigor/UniverseRobustness.hx` — single-name flagged.
  **Live:** CorpusEvoRun `[rigor universe]` on `--tapes` basket for best host; single-`--tape` always
  NO-GO on universe gate (honest). Hardened OOS CLI flags single-tape runs.

## Bucket C — LEAKAGE & PIT DISCIPLINE (P0)

- [x] **C1. Host causality audit.** Standing probes for Lattice / Mcmc / Regime / Auction in
  `TestPitDiscipline` (+ stub/null/oracle in `TestPipelineHardening`). Regime `cloudAt(t)` fixed to
  use closes ≤ t only. Probe streams `0..t` by default (materialize contract); `fullStream` for
  history-retaining hosts (Auction/Regime).
- [x] **C2. Benchmark target boundaries.** Tests: last-H NaN, PLevel = close[t+h] ≠ close[t],
  forwardRange ignores bar t, future mutation moves target. `ProjectionScore.realizedTarget` audited.
- [x] **C3. `decorateBars` / `materialize` causality.** Decorated `p50` equals independent streaming
  `cloudAt(t)`; prefix materialize matches full-tape prefix (no future preload).
- [x] **C4. Warmup honesty.** `ew/HostWarmup.hx` documents CLI defaults; `isLegalAnchor` wired into
  Ew/Regime/Auction benchmark CLIs; host-floor tests for regime/auction empty clouds.

## Bucket D — DETERMINISM & RNG QUALITY (P1)

Files: `ew/mcmc/DetRng.hx`, `DetMath.hx`, `DetParityDump.hx`.

- [x] **D1. RNG statistical battery.** Chi-square uniformity, `nextInt` no-mod bias, lag-1 ≈0 in
  `TestP1Hardening`.
- [x] **D2. Gaussian quality.** Moments + Marsaglia-pair lag-1 in `TestP1Hardening`.
- [x] **D3. DetMath accuracy + edge cases.** log/exp rel error + NaN/overflow edges.
- [x] **D4. Extend the parity gate.** `DetParityDump.render()` + golden
  `testdata/det-parity.golden.txt` (utest); JVM↔node auto-diff via
  `tools/det_parity_ci.ps1` / `tools/det_parity_ci.sh`. **CI:** `.github/workflows/pipeline-hardening.yml`
  runs `det_parity_ci.sh`.

## Bucket E — FORECAST SUBSTRATES (P1 — per-host correctness + theory)

- [x] **E1. RegimeMcmc convergence & mixing.** `essFromTrace` / `essCurrentRegime` / `mixingOk`;
  constant-trace ESS = N; accept-band + short-budget tests.
- [x] **E2. RegimeMcmc calibration.** Predictive p05–p95 ~90% coverage test.
- [x] **E3. Auction / VolumeProfile audit.** VA fraction ≥ target; POC in VA; golden histogram
  (exact heavy-bin volumes + POC=104.5); bin-sensitivity POC stable near heavy print.
- [x] **E4. EW rule completeness.** `TestFrostAdversarial`: bull/bear valid, W2>W1, W4>W3,
  W3-not-beyond, W3-shortest, non-alternation, W4-overlap→diagonal, trunc fifth, zigzag/flat
  kinds, soft guidelines [0,1], named adversarial battery.
- [x] **E5. ForecastCloud invariants.** `HostLeakageProbe.checkInvariants` parameterized over all four
  production hosts in `TestPitDiscipline.testProductionHostsEmitInvariantClouds`.

## Bucket F — CO-EVOLUTION MACHINERY (P1)

Files: `evo/Variation.hx`, `Simplify.hx`, `ProjectionProvider.hx`, `CorpusSeed.hx`, `Expand.hx`,
`evo/nma/NmaNodeEvalPool.hx`, `Canonical.hx`.

- [x] **F1. Struct-rebuild field-drop audit (the drain-bug class).** `RivalryArena.paramBlendToward` +
  `NmaSemanticRdo.spliceBool` keep projections; rivalry + compactParams tests.
- [x] **F2. NmaNodeEvalPool JSON-serialization leak.** `assertWorkerJsonSafe` refuses projection genomes
  on multi-worker path (no silent strip).
- [x] **F3. ProjectionProvider binding/caching correctness.** Tape-swap invalidate + prefix≠full bind key.
  *(decorate auto-bind end-to-end collision suite thinner.)*
- [x] **F4. Reinject / drain guard.** compactParams / simplify regressions; `HostDrainGuard`
  (CorpusEvoRun uses `countHostAlive` + `reinjectEvents`); mutate+simplify decl drain rate ≈0.
- [x] **F5. Seed integrity.** Regime/auction seeds drop dead `vs_invalidate`; lattice keeps it.

## Bucket G — BACKTEST & COST ACCOUNTING (P1)

Files: `harness/OrderSim.hx`, `BacktestEngine.hx`, `HarnessContext.hx`, `Fitness.evaluate`.

- [x] **G1. Cost model honesty (turnover).** Slippage monotonic on entry/exit + flip vs free.
- [x] **G2. Sizing semantics.** `riskCappedQty` clamps explicit oversize to 25% cash.
- [x] **G3. Fill realism.** `next-open` defers fill; flip = close+open (3 trade counts).
  *(Limit/stop book path already covered in `TestOrderBook`.)*
- [x] **G4. Bankruptcy/equity-floor.** Bankrupt → NEG_INF under `defaultMinTrades=20`.

## Bucket H — DATA INTEGRITY (P2)

Files: `harness/OhlcvCsv.hx`, `harness/TapeLinter.hx`, the tapes.

- [x] **H1. Tape sanity.** `TapeLinter`: OHLC relations, finite/positive prices, volume ≥ 0,
  empty-tape error. Tests + standing lint of `data/real/tsla.csv`.
  **Live:** CorpusEvoRun `loadBars` + `BenchmarkHarness.loadBars` abort on lint errors.
- [x] **H2. Look-ahead in data.** Strictly increasing time, duplicate-time error, index mismatch warn,
  large-gap warn. Time regression = ERROR (shuffle/look-ahead risk).
- [x] **H3. Realized-vol / realized-target computation.** Last-H NaN, PLevel uses future close,
  forwardRange ignores bar t, PVol finite & ≥0, future mutation moves target (`TestTapeLinter`).

## Bucket I — BENCHMARK RUNNERS (P1)

Files: `ew/EwBenchmark.hx`, `EwBenchmarkCli.hx`, `EwProfitCli.hx`, `RegimeBenchmarkCli.hx`,
`AuctionBenchmarkCli.hx`.

- [x] **I1. Null-baseline strength audit.** Docs + empirical collapse: persistence Δvol IC≈0 on
  i.i.d.; random auction class edges≈0; ATR null tight≪wide on thin tape; constant rank-IC=0.
- [x] **I2. Metric-gaming audit.** Constant predictor → 0 rank-IC (reconfirmed in P1 suite).
- [x] **I3. Shared harness.** `BenchmarkHarness` loadBars / requireTapeLength / isLegalAnchor /
  anchorGrid; Ew/Regime/Auction/Profit CLIs delegate `loadBars` (**now TapeLinter-gated**).

## Bucket J — META CONTROLS (P0 — the tests-of-the-tests; do these FIRST and LAST)

These make false positives nearly impossible by validating the instrument itself.

- [x] **J1. NEGATIVE CONTROL (must FAIL).** `ew/NullForecastHost.hx` + OOS verdict / min-trade tests —
  noise → NO-GO. Wired into `TestPipelineHardening` (standing CI via TestMain / projection-host suite).
  Also asserted inside `testJ2PlantedEdgeEvoOosGoWhileNullNoGo`.
- [x] **J2. POSITIVE CONTROL (must PASS).** `ew/OracleForecastHost.hx` — signal monotone skill test
  **plus** standing e2e DoD: planted-edge genome → IS `rankScore` selection vs null → hardened OOS
  → **GO** (`testJ2PlantedEdgeEvoOosGoWhileNullNoGo`). Full multi-gen CorpusEvoRun planted co-evo on
  a long real tape is still a heavier optional live check (not required for the standing gate).
- [x] **J3. Label-shuffle test.** Shuffle collapses rank-IC (~0). In `TestPipelineHardening`.
- [x] **J4. Standing CI gate.** `TestPipelineHardening` registered in `TestMain` +
  `TestProjectionHostMain`. **Automated:** `.github/workflows/pipeline-hardening.yml` runs
  projection-host + auction suites + `tools/det_parity_ci.sh`.

---

## Suggested order
J1 + J3 (build the negative controls FIRST — they'll immediately expose the thin-trade leak and any
others) → Bucket A (fix the leak) → J2 (confirm we can still detect real edge) → Bucket C (leakage) →
Bucket B (rigor) → then P1 buckets D–I in any order → re-run J1/J2/J3 at the end.

**Definition of done for the whole pass:** J1 rejects noise, J2 detects planted edge scaling with
strength, J3 collapses under shuffle, and re-running the auction/EW/regime comparisons through the
hardened instrument reproduces the honest NO-GOs (no resurrected false pulses). Only THEN is a future
"GO" believable.

### Remaining soft (honest)

| Soft spot | Status |
|-----------|--------|
| Multi-CLI-seed restart matrix (`--seed` grid → SeedRobustness) | Not wired — elite/host-seed median is live instead |
| Full CorpusEvoRun multi-gen planted-edge co-evo on real tape | Standing test covers minimal evo path; full JVM run optional |
| `--prereg` hard abort vs champion | Flag + WARNING only; PreRegistration helper remains library-grade |
| Universe GO on single-name research tapes | Correctly NO-GO; need `--tapes` multi-name for universe GO |

---

## Key new / changed files (this pass)

| Area | Path |
|------|------|
| Rigor | `musescript/evo/rigor/{NormApprox,ProbSharpe,BlockBootstrap,Pbo,PurgeEmbargo,PreRegistration,SeedRobustness,UniverseRobustness,OosVerdict,TruthReport,TruthVerdict,TrialsSession}.hx` |
| Controls | `musescript/ew/{NullForecastHost,OracleForecastHost,HostLeakageProbe,HostWarmup,BenchmarkHarness}.hx` |
| Gate | `musescript/evo/Fitness.hx` (`defaultMinTrades`, `scoreNullBaseline`, `rankScore`, `rankScoreFacts`) |
| OOS | `musescript/evo/graal/CorpusEvoRun.hx` (`--min-trades`, `--n-trials` default 50, `--no-rank-dsr`, `--prereg`, TapeLinter, live PBO/seed-median/universe) |
| PIT | `musescript/ew/RegimeForecastHost.hx` (t-causal closes); `*BenchmarkCli` → `HostWarmup` / `BenchmarkHarness` |
| MCMC | `musescript/ew/mcmc/RegimeMcmc.hx` (ESS / mixingOk); `DetParityDump` + `testdata/det-parity.golden.txt` + `tools/det_parity_ci.*` |
| Drains | `HostDrainGuard`, `RivalryArena`, `NmaSemanticRdo`, `NmaNodeEvalPool.assertWorkerJsonSafe`, `CorpusSeed` |
| Metrics | `musescript/evo/ProjectionScore.hx` (`minSample=10`) |
| Auction | `VolumeProfile.histogram`; `AuctionHardenedOosCli` (`--host-kind`, seed-median, universe flag) |
| Data | `musescript/harness/TapeLinter.hx` (H1–H3); CorpusEvoRun + BenchmarkHarness lint on load |
| CI | `.github/workflows/pipeline-hardening.yml` |
| Tests | `musescript/tests/{TestPipelineHardening,TestPitDiscipline,TestP1Hardening,TestFrostAdversarial,TestDetParity,TestTapeLinter}.hx` |
