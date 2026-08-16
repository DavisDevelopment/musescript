# Open items (aggregated + tree-triaged)

Mined from deleted root plans (2026-08-07), then verified against the current tree the same day.

**For collaborators:** triage backlog, not a product contract. Start with [README.md](README.md) +
[CONTRIBUTING.md](CONTRIBUTING.md). Prefer a focused issue/PR over editing this table day-to-day
unless you are intentionally grooming it.

Repo root docs for humans: `README.md`, `CONTRIBUTING.md`, `docs/*`, and this file.

**Legend:** still real · **done (pruned)** · landing residual · deferred / needs lock
---

## Active — MuseScript core

| # | Action | Evidence / note | Status |
|---|--------|-----------------|--------|
| 1.1 | Finish `RingBuffer` migration; drop remaining `.shift()` in `indicators/lib/` | **0** files still call `.shift()` (was 29→0 this pass; prior 48→29, 65→48, 85→65, 103→85). Migrated this pass (all remaining): AndrewsPitchfork, AutocorrelationPeriodogram, CompositeProfile, EmpiricalModeDecomposition, FourierDecompose, FourierDominantPeriod, FourierProjection, FourierRecompose, HighLowVolumeNodes, Ichimoku, KasePermissionStochastic, PivotReversal, ProfileShape, RegimeLabel (retWindow), SampleEntropy, SinglePrints, TdCombo, TdCountdown, TdDemarker, TdDwave, TdPressure, TdRei, TdSequential, TpoProfile, UlcerIndex (drawdownsSq ring + deque head; no `.shift()`), ValueArea, VolatilityCone (returns ring), VolumeProfile, VolumeWeightedSr. IndicatorGolden empty + port batches 03/14/24/27/28/30/34/35/38/39/41/42/43/44/45 + TestFourierBuiltins green. **§1.2 unblocked.** | done |
| 1.2 | After 1.1: build lint ban `.shift()` in `indicators/lib/` | **Landed.** Fail-closed on `.shift(` (not `unshift`) in `musescript/indicators/lib/` only: compile-time `IndicatorRegistryMacro.checkShiftBan`, utest `TestIndicatorLibHygiene`, `node tools/ban_indicator_shift.mjs` (engine-matrix preflight + pipeline-hardening CI). RingBuffer grind stays locked; `prim/` out of scope. | done |
| 1.3 | Window-re-sort indicators → sorted-insert / ring | **0** `.sort(` in `indicators/lib/` (was 15→7→3→1→0). Landed this pass: SpearmanCorrelation — dual `SortedWindow` spines + mid-tie table/`lower_bound` chrono materialization; full Pearson kept (Δ-Pearson of ranks still ULP-hostile — out of scope). Prior: MAD abs-dev, BomarBands fold-merge; ALF / RegimeLabel / VolCone / CVaR; MedianMa/Channel, RollingQuantile/Iqr, QuartileBands, VaR, TailRatio, CommonSenseRatio. IndicatorGolden empty + TestPortBatch41 green | done |
| 1.4 | Wire real bar resolution into Sharpe `periodsPerYear` | **Landed.** Ownership: `Metrics.periodsPerYear` (default **252**). Opt-in `configureFromBars` / `Fitness.configurePeriodsFromBars` (daily≈86400 → 252, not 365; sub-daily → `periodsPerYearFromBarSeconds`). Wired through Metrics.sharpe/sortino, OrderSim.sharpeOnline, NmaFitness, Fitness window/ProbSharpe, FitnessOpts→Nma workers, signal-memo digest. No auto-infer on `evaluate` (synthetic `i*60` + goldens stay 252). | done |
| 1.5 | `MurmurationRng`: 32-bit-safe math (`haxe.Int32` or validated 32-bit triple) | **Landed.** `haxe.Int32` `imul32`/`iadd32` + Int32 xorshift/mix (same footgun class as `Rand`/`BarFeed`). JVM/interp stream unchanged; pre-fix JS corrected to match. Goldens + same-seed determinism in `TestMurmuration` | done |
| 1.6 | **M2** `spec()` arity/types vs arg readers | Not audited this pass | open |
| 1.7 | **M4** refuse Sharpe/vol without explicit periods outside daily | After 1.4 plumbing — still deferred (no refuse yet; default 252 remains silent) | deferred |
| 1.8 | **M5** builtins missing docs / Pine-map coverage report | Not audited this pass | open |
| 1.10 | `NmaFuseHost` JS mem / JVM bulk path before default-on | Host exists; flag `--nma-fuse-host`; auto-off when `threads > 1` | open |
| 1.11 | Widen WASM fuse beyond BAnd/BOr; measure; default-on | Fuse host present; still opt-in | partial |
| 1.12 | `SymbolSelector` `Array<Float>` → FloatSeries/GrowableVec | Still `weights:Array<Float>` / `score(features:Array<Float>)` | open |
| 1.13 | Wickra Tier-1 grind (rsi/atr Wilder re-pin separate) | Inventory may be stale — re-count before grind | partial |
| 2.1 | Widen residual VM `IND`/opaque builtins | Standing next VM lever | open |
| 2.5 / 2.8 | Re-measure VM/evo benches with fresh jars (no live CorpusEvoRun) | Measurement debt | open |
| 2.7 / 2.11 | Standing: MuseVmOps↔interp lockstep; never rebuild jar mid-run | Process | standing |
| 2.12 | Multi-thread `--nma` determinism probe (gates parallel NMA) | **LANDED both targets.** Node: `NmaNodeBench --det-probe` / `scripts/nma_thread_det_probe.ps1`. JVM: `CorpusEvoRun --det-probe` / `scripts/nma_jvm_thread_det_probe.ps1` (real fb Deque pool). N=64×M=2,4×K=3 green vs serial on smoke tape | done |
| 2.13 | Attack EvolutionEngine.step / Variation / attribution cost | Still the Amdahl story if you want big multiples | open |
| 2.14 | V8 deopt script + Electron TurboFan + worker_threads evo pool | Not verified present | open |
| 3.1 | Author holes P1: `SHole` / series holes; Studio “Fill holes”; CLI polish | `BHole`/`KHole` + `Variation.fillHoles` + `TestAuthorHoles` landed; **no `SHole` in SeriesNode**; comment says Series holes are P1 | partial |
| 3.2 | Macro hygiene / expander consolidation / recursive templates | Language-eval debt | open |
| 3.3 | Class-strategy gaps beyond current wiring | `ClassStrategyLower` is on MuseRuntime/Compiler/GeneRunner/Debug/CorpusSeed/HonestOptimize + tests — **kept open at peer request** (known residual gap) | open — verify gap |
| 3.4–3.7 | Candle genome `SCandle`, `count_recent`/`held`, `pattern {…}`, cross-bar vocab | No `SCandle` / `count_recent` / held builtin hits | open |
| 4.1 | Native `NmaSProj` (today SProj → ProjInline / nma-unsupported) | `NmaBijection` still throws on `SProj` | open |
| 4.7 | Columnar NMA for gated `KPd("xs_rank")` | **Landed.** Packed `pd_rank1d` ≤64 + `field@SYM` scores via `NmaEval` / `Expand.pdXsRankNmaEligible`. Wide `\|universe\|>64` / unknown kinds / no panel pack stay Expand. `evaluateVm` still refuses panel xs_rank. | done (residual: wide frame) |
| 4.2–4.5 | Expand proj runtime leftovers; CRPS-as-fan-score; multi-seed A/B; use-weighted projScore | Ew CRPS + Fitness.projScore exist; full P1–P4 residuals still real | open / partial |
| 4.6 | Full CCEA beyond crisp `--ccea` vertical | Epic | deferred |

## Active — Flagship harness

| # | Action | Evidence / note | Status |
|---|--------|-----------------|--------|
| 6.1a | Byte-identical: cold `run_gene` vs warm `run_gene_batch` on top-9 meanrev | `harness/batch_identity.py` — 540 strat + 60 BH cells, exact sharpe/MDD/trades/pass | done |
| 6.1b | Time 9× meanrev corpus_score — target ≪ 1 min | Warm wall **1.49s** for 600 jobs (was 9–18 min cold spawn); cold recheck 226s | done |
| 6.1c | Coalesce `cmd_matrix` into one mega-batch across honesty×freq slices | `run_matrix_mega` + `batch_matrix_coalesce.py`: mega **1 spawn / 3.56s** vs legacy 6 / 21.15s; metrics exact | done |
| 6.1d | Optional: corpus/bull CLI publish into viz_state | Soft | deferred |
| 6.2 | Phase 2 Mederos `--cli-tool=` | Do not build until 2nd/3rd tool | deferred |

**Phase 1 plumbing: LANDED** — `build-batch.hxml`, `build/js/batch-runner.js`, `eval.run_gene_batch`, score_probe / corpus_score / bull_score / viz_core wired.

## Active — IDE / product (outside or cross-repo)

| # | Action | Status |
|---|--------|--------|
| 8.1 | MuseNotebook Truth Report panel | open |
| 8.3 | Report Card universe / seed sweep / per-symbol OOS / share art | open |
| 8.5 | Deploy durable relay | blocked on ops |
| 8.6 | Forge / Blueprints Phase 6 polish | open |
| 8.4 | On-device LLM | deferred — needs lock |
| 9.1–9.4 | Geospatial roads/traffic/pop — needs locks | open / locked CRE only |
| 9.5–9.6 | Topics rename; interest_alert bus | deferred |
| 9.7–9.11 | **WorldFrameHost P0+** — `eventStreams["world"]`, `cf_diff`, shock listener | **open** (only orderFlow/ticks streams found; no WorldFrameHost) |
| 9.13–9.16 | MiroFish/Prophet/GSID reimplement steals | open |

## Deferred packaging / optional soaks

| # | Action | Status |
|---|--------|--------|
| 2.2–2.3 / 2.6 | VM P3/P4 / Tier B Truffle | deferred research |
| 2.9–2.10 / 2.16 | Evo flag re-A/B; native parser Stage C soak then default | deferred |
| 5.* | Pipeline soft soaks / multi-tape universe GO process | deferred / standing |
| 7.* | npm/pip muse-script packages | deferred — desktop-tools first |
| 1.14–1.15 | OrderBook impact; promote N-of-M | deferred |

---

## Pruned as done (or obsolete as stated)

| Former # | Why pruned |
|----------|------------|
| 1.9 TradeBuiltins.zscore `for..in` | `zscoreN` uses indexed loops over resolved series |
| § Audit triage WPs | Previously shipped; not reopened |
| Bytecode VM P0–P1 / preferVm / unboxed stack / TB0 IND | Checklist landed; only residuals above remain |
| Author holes P0 (BHole/KHole transparency + fillHoles + OOS honesty) | Tests exist; only P1 series holes remain active |
| Batch Phase 1 build itself | Landed; residual **6.1d** (6.1a–c done) |
| 6.1a–b warm batch identity + timing | `batch_identity.py`: exact match 540+60 cells; warm 1.49s |
| 6.1c matrix honesty×freq mega-batch | `batch_matrix_coalesce.py`: 1 spawn; exact vs per-slice |
| Forge Phases 0–5 DoDs | Historical; Phase 6 only active |
| Business Interest P0–P3 spine | Marked shipped in source plan; residuals listed above |
| Uncertainty bands from spkmc | Prior plan said landed |

---

## Suggested next grind (post-triage)

1. **6.1d** / **3.3** — optional viz publish, or hunt remaining class-strategy gap
2. **1.6 / 1.8** — spec() arity audit, or builtins docs / Pine-map coverage
3. **9.7** — WorldFrameHost only after D6 lock

### Human locks still needed

- Geospatial roads / traffic / pop (**9.1**)
- WorldFrameHost home CLI vs haxelib (**9.7**)
- Whether 3.3 gap is Runtime/Studio/docs — peer believes one remains
- Packaging resume (**§7**)
- **1.7 / product default:** whether sub-daily tapes should auto-`configureFromBars` at CLI/CorpusEvo load (or require explicit `--periods-per-year` / M4 refuse). 1.4 ships opt-in only so goldens stay 252.

---

## Deleted sources

`ALGORITHM_AUDIT.md`, `AUDIT_TRIAGE_AND_DELEGATION.md`, `BYTECODE_VM_TODO.md`, `CLAUDE_HANDOFF.md`, `CURSOR_BATCH_RUNNER_SPEC.md`, `FORGE_OVERHAUL_PLAN.md`, `JORMUNGANDR_*` (5), `LANGUAGE_EVALUATION.md`, `NPM_PACKAGE_PLAN.md`, `PIP_PACKAGE_PLAN.md`, `PIPELINE_HARDENING_TODO.md`, `PLAN_EVO_SPEED.md`, `polishpass_notes.md`, `PROJECTION_COEVOLUTION_PLAN.md`, `REPORT_CARD_LEDGER_HANDOFF.md`, `ROADMAP.md`, `SHIP_PROTECT.md`, `SPEC_*` (3), `STORY.md`, `TERMINAL_IDE_PRODUCT_GOALS.md`, `TIER_B_BUILD_PLAN.md`, `TRUTH_REPORT_IDE_HANDOFF.md`, `VM_PERF_TRAIL.md`, `WEB_SURFACE_PARITY_PLAN.md`

Batch usage live doc: `examples/flagship-musescript-module/harness/BATCH_RUNNER.md` (kept — not root bloat).
