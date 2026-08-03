# Evolvable Projections + Co-evolved Forecaster/Manager Pairs — design plan

**Date:** 2026-07-27 (live vertical landed 2026-08-03; CCEA crisp vertical 2026-08-03)
**Status:** LIVE VERTICAL — genome with `SProj` → purged skill axis → MAP-Elites selectable;
decorate→pack for hosts; **CCEA two-pop smoke** (`--ccea`) with coupled trading fitness.
Remaining: CRPS / native `NmaSProj` / `NBlockBootstrap` / full Red-Queen CCEA.

---

## 0. One-paragraph intent

Let a genome define one or more **projections**: named, point-in-time-causal series/scalars it
computes each bar, *hypothesized to have a patterned relationship to the future timeseries*. A
projection is (a) a **variable the policy can read** (`proj_0`, `proj_0[k]`, `crossover(proj_0, …)`),
and (b) a **scoreable object** whose predictive skill vs realized future values is measured
leakage-free. With both in place, the evolution engine co-adapts a **forecaster module** and a
**portfolio-management module** — the manager is only as good as the forecasts it's fed, and a
forecast only earns credit if a manager actually exploits it. Fitness credits both realized trading
performance and honest, out-of-sample forecast skill.

**The whole game is leakage.** A projection is built from the *same* PIT feature set as everything
else (data ≤ t only). "Forward-looking" is a property of how we **interpret and score** it, never a
data-access privilege. Every skill measurement compares a projection at bar *t* to values strictly
after *t*, on purged/embargoed out-of-sample splits. A projection that can see the future is a bug,
not a feature.

### Decisions locked (2026-07-27)

1. **Multi-series first-class.** A projection is a `K≥1`-series Monte-Carlo fan; the deterministic
   point projection is `K=1`. The bundle shape lands in P0 so MC needs no migration (§2).
2. **Selection = MAP-Elites** with forecast skill as a behavioral-descriptor axis (CVT), *not* an
   additive fitness weight. `--proj-weight` survives only as a P3 smoke knob (§7).
3. **v1 = intra-genome two-module co-evolution** (one genome carries both modules, module-aware credit
   via projection-ablation). **v2 CCEA two-pop** now has a crisp vertical (`CceaCoEvo` / `--ccea`);
   full Red-Queen / multi-partner remains gated.

---

## 1. What exists today (the seams we hang this on)

| Piece | Shape | Relevance |
|---|---|---|
| `StrategyGenome` | `{ entryLong, entryShort, exitLong, exitShort: BoolNode; size: ScalarNode; params: EvoParam[]; name; lineage }` | Add a new **projection root**; keep it `?`-optional so existing genomes are byte-identical |
| `SeriesNode` | `SPrice(field) \| SInd(name, field, window, ?src)` | Add `SProj(name)` so policy trees consume projections through the *existing* series grammar |
| `ScalarNode` | `KConst \| KParam \| KArith \| KSeries \| KLookback \| KFeature \| KHole` | `KSeries(SProj)` / `KLookback(SProj, k)` read a projection as a scalar for free |
| `BoolNode` | `BCross \| BCmp \| BTrend \| BAnd \| BOr \| BNot \| BHole` | `BCross(SProj, …)`, `BTrend(SProj, w)`, `BCmp(KSeries(SProj), …)` all work with no new bool node |
| `Expand.expand(g)` | renders `strategy N(p){ onBar { when(cond)&&…: {long(size)} … } }` | Inject projection `let` bindings into the `onBar` prelude before the guards |
| `Fitness.evaluate(g, bars, target, verify?, ?costBps) -> FitnessResult` | `{ ok, sharpe, trades, finalEquity, backend, error, fills, bankrupt, equity }` | Add optional `projScore`/`projScores`; combine in `score`/`robustScore` |
| `NmaEval.evalSeries` | columnar, memoized-by-epoch, kind-switch | `SProj` resolves to the projection's own column; policy reads it as a column reference |
| `NmaFeatureHost` | `KFeature` = bare-identifier variables (position vs tape-pure) | Projections are the *evolvable* cousin of features; the position-feature/tape-pure split is the template for the causal/leakage split |
| `Canonical` / `BHole`/`KHole` | transparent markers, cache-neutral | Precedent for adding an optional genome element that is a no-op when absent |
| MAP-Elites / lexicase / novelty (memory) | descriptor-binned elites, case fitness | The natural home for forecast-skill as a **quality axis or descriptor**, i.e. co-evolving *pairs* as niches |
| Attribution oracle / `NmaCreditBank` / `GrowthWeights` (memory) | subtree-ablation credit | Extend to a **projection-ablation** so a projection is credited by how much the policy actually uses it |
| Validation rigor: PIT oracle, purge/embargo, PSR/DSR/PBO (memory) | leakage layers | Mandatory substrate for scoring projection skill honestly |

---

## 2. Genome schema change — bundle-shaped from day one (single series = K=1)

A projection is a **sampler that emits `K ≥ 1` series** — an ensemble / Monte-Carlo fan. The
deterministic single-series "thought" is simply `K = 1`. We land the *bundle* shape in P0 even for
the deterministic case, so multi-series MC **never requires a schema migration** — it is the general
form, and the point projection is its degenerate instance. This mirrors the existing multi-output
`SInd` precedent (`macd → {macd,signal,hist}`, `bbands → {upper,mid,lower}` — `NmaFeatureHost`).

```haxe
// StrategyGenome — add ONE optional root. Absent ⇒ byte-identical to today (parity discipline).
var ?projections:Array<ProjectionDecl>;

typedef ProjectionDecl = {
  var name:String;       // "proj_0" — the identifier the policy references
  var kind:ProjKind;     // what future quantity it forecasts (fixes the scoring target — §6)
  var horizon:Int;       // H bars ahead this projection claims a relationship to
  var sampler:ProjSampler; // evolvable structure that produces 1..K series (the fan)
  var samples:Int;       // K. 1 ⇒ deterministic point projection (v1). >1 ⇒ MC fan.
  var seed:Int;          // deterministic MC — seeded PRNG (mulberry32-style, like mobile ForwardSim)
                         // so a fan is STABLE across re-renders/re-evals: same genome ⇒ same K paths.
}

// The fan generator. Evolvable. Deterministic case is a first-class variant, not a special flag.
enum ProjSampler {
  // K=1 exactly: the single PIT-causal series. This IS the §1–§3 point-projection design.
  PSPoint(node:SeriesNode);
  // K seeded draws: a base path + an evolved per-bar volatility scale + a noise process.
  // Draws are causal — noise at bar t uses only the seed + info ≤ t (NOT future residuals at eval
  // time; block-bootstrap of PAST residuals is fine, it only reads ≤ t).
  PSNoise(base:SeriesNode, vol:ScalarNode, model:NoiseModel);
  // (later) PSMixture(components), PSRegime(switch, samplers) — deferred; enum leaves room.
}

enum NoiseModel {
  NGaussian;        // scaled i.i.d. normal
  NBlockBootstrap(block:Int); // resample PAST return blocks (≤ t) — the mobile ForwardSim default
  NStudentT(dof:Int);
}

enum ProjKind {
  PReturn;    // forward return  (close[t+H]/close[t] - 1)
  PDirection; // forward sign    (sign(close[t+H]-close[t]))
  PLevel;     // forward level   (close[t+H])
  PVol;       // forward realized vol over (t, t+H]
  PRange;     // forward high-low range over (t, t+H]
}
```

Design decisions baked in:
- **A projection is a `ProjBundle` = `K` series columns** (§5). `K=1` is the point case; `K>1` is the
  MC fan. Nothing downstream assumes `K=1` — the policy reads *fan reductions* (§3), the scorer scores
  a *distribution* (§6), and both degenerate cleanly at `K=1`.
- **Determinism is mandatory** (`seed` + seeded PRNG). A fan must be identical across the fitness pass,
  the attribution ablations, and the champion re-check — otherwise caching and same-seed A/B parity
  (§9) break. Same discipline as `Rand`/`RngStreams` already in `evo/`.
- **Optional-typed root.** `projections == null` renders and scores exactly as today (`BHole`/
  `equityFloor` parity trick: additive, default-inert).
- **Names are dense (`proj_0`, …).** Variation only emits `SProj(name, field)` for a declared name +
  a valid fan-reduction field; undeclared refs are unreachable by construction (validated in
  `Canonical`/`Variation`, like param indices and the projection-name DAG in §5).

---

## 3. Grammar: how the policy reads the fan

One new series node — with a **fan-reduction `field`** (exactly the multi-output `SInd(name, field,
…)` shape). The `field` collapses the `K`-series bundle into one readable series; the entire existing
scalar/bool grammar then composes over each reduction.

```haxe
// SeriesNode
SProj(name:String, field:String);   // read a fan-REDUCTION series of the named projection
```

**Fan-reduction vocabulary** (`field`) — each is a per-bar series derived from the `K` samples at
that bar. At `K=1` every quantile/mean collapses to the single value and `spread`/`prob_up` degenerate
(spread=0), so a point projection reads identically whichever field it picks:

| field | meaning | K=1 degeneracy |
|---|---|---|
| `p05 p25 p50 p75 p95` | empirical quantiles of the fan at each bar | all = the single value |
| `mean` | ensemble mean | = the single value |
| `spread` | `p95 − p05` (fan width / uncertainty) | 0 |
| `prob_up` | fraction of samples above a reference (e.g. current close) | 0 or 1 |
| `sample_i` | the i-th raw path (bounded `i < K`) | the single value |

- `KSeries(SProj("proj_0", "p50"))` — median forecast as a scalar
- `KLookback(SProj("proj_0", "p50"), k)` — median forecast k bars back
- `BCmp(">", KSeries(SProj("proj_0","prob_up")), KConst(0.6))` — "≥60% of paths point up"
- `BCross("over", SProj("proj_0","p50"), SPrice("close"))` — "median forecast crosses price"
- `BCmp("<", KSeries(SProj("proj_0","spread")), KParam(iMaxUncertainty))` — **trade only when the fan
  is tight** (uncertainty-gated sizing — the MC fan's whole point: the policy can react to *confidence*,
  not just direction)

No new bool/scalar node types. `Palette`/`RegistryPalette` gain `SProj` as a growable series leaf,
**bounded to (declared projection name × valid field)** — a mutation referencing a nonexistent name,
or `sample_i` with `i ≥ K`, is rejected at catalog-build time. This is the minimal grammar surface
that makes a whole MC fan first-class policy input.

---

## 4. Rendering (`Expand`): projections are `onBar` prelude `let`s

```
strategy N(params) {
  onBar {
    // Sampler realized by the ProjectionProvider (see §5); each REFERENCED fan-reduction
    // binds to one prelude let. PSPoint reductions all alias the single series.
    let proj_0__p50    = project("proj_0", "p50")
    let proj_0__spread = project("proj_0", "spread")
    when (<entryLong reading proj_0__p50>) && position() <= 0: { long(<size>) }
    when (<entryShort>)                    && position() >= 0: { short(<size>) }
    when (<exitLong>) || (<exitShort>): { flat() }
  }
}
```

- `Expand.series(SProj("proj_0","p50"))` → the identifier `proj_0__p50`, bound by a prelude
  `let proj_0__p50 = project("proj_0","p50")`. **Only referenced (name, field) pairs are emitted** —
  an unread reduction costs nothing.
- **`project(name, field)` is the one new builtin** (sibling of the indicator builtins): it asks the
  ProjectionProvider for the fan reduction, causally. The `PSPoint` (K=1) case can render its inner
  `SeriesNode` inline instead of going through the builtin — an optional fast path; both are
  bit-identical since every reduction of a 1-sample fan is the sample.
- Prelude `let`s are the strategy-surface's field semantics (per-bar re-evaluation) — no new language
  concept beyond the one builtin. The whole genome stays on the **compiled/columnar** path.
- **Parity anchors (P0 tests):** (a) `projections == null` renders byte-for-byte as today; (b) a
  declared-but-unreferenced projection emits *no* `let` and scores bit-identically; (c) a `PSPoint`
  projection read via the builtin vs rendered inline produce identical columns.

---

## 5. Columnar / NMA evaluation — a fan is `K` columns + derived reductions

- **`ProjBundle`** = the realized fan for one projection at one tape/epoch: `K` sample columns
  (`GrowableVec<Float>` / `FloatSeries` each) + a lazily-derived **reduction table** keyed by field
  (`p05…p95`, `mean`, `spread`, `prob_up`, `sample_i`). Reductions are per-bar functions of the `K`
  samples (a per-bar sort or running-quantile over `K` — `K` is small, cap ~16). `PSPoint` builds a
  1-column bundle where every reduction aliases the single column (no sort, no extra alloc).
- **`ProjectionProvider`** (sibling of `NmaIndicatorProvider` → `EngineIndicatorProvider`): owns
  sampler realization so **interp / JS / NMA stay bit-parity** the same way indicators do. It:
  1. realizes each `ProjSampler` into a `ProjBundle` once per (tape, projection, seed),
  2. answers `project(name, field)` / `SProj(name, field)` with the reduction column,
  3. seeds the PRNG deterministically from `decl.seed` (+ tape signature) so the fan is identical
     across the fitness pass, attribution ablations, and champion re-check.
- **`NmaEval` `SProj` arm:** resolve `(name, field)` → the provider's reduction column, then memoize
  by epoch and content-address per the JIT guide (§26/§31). A fan shared across the population dedupes
  like any column; the reduction table dedupes within a bundle.
- **Cost is real and bounded:** a `K`-sample fan is `K` columns + reductions per projection. Cap `K`
  (§11 Q2), cap projections/genome, and parsimony-penalize both — an evolved 16-path fan on 3
  projections is 48 columns, so this is gated and measured (JIT audit / `--phase-profile`) before
  default-on. The single-series `K=1` path adds ~one column, negligibly more than today.
- **Causality is structural:** sample columns are built from the same `≤ t` inputs as `SInd` columns
  (`PSNoise` block-bootstrap resamples PAST residuals only). No code path lets a sample read a future
  bar. Forward data appears **only** in the scorer (§6), never in the eval the policy consumes.
- **Dependency ordering:** `SProj` may reference an *earlier* projection (`proj_1`'s sampler may read
  `proj_0__p50`) but not itself or a later one — a DAG over projection names, topologically resolved
  once per epoch. Cycles rejected in `Canonical` (same class of check as param-ref validity).

---

## 6. Projection scoring — the honest core (the new fitness term)

For each `ProjectionDecl` with kind `K` and horizon `H`, over the scoring window:
- At bar *t*, take the PIT projection value `p_t` (the projection column) and the realized target
  `y_t = f_K(future[t+1 .. t+H])`:

| kind | realized target `y_t` | default skill metric |
|---|---|---|
| `PReturn` | `close[t+H]/close[t] - 1` | rank-IC (Spearman) between `p` and `y` |
| `PDirection` | `sign(close[t+H]-close[t])` | directional accuracy / MCC / AUC |
| `PLevel` | `close[t+H]` | corr(`p`, `y`) or 1 − nMAE |
| `PVol` | realized vol over `(t, t+H]` | corr(`p`, `y`) |
| `PRange` | `max(high) − min(low)` over horizon | corr(`p`, `y`) |

- **`ProjectionScore` = a bounded, sign-meaningful skill scalar** (default **rank-IC** on the point
  case: robust to scale/outliers, 0 = no skill, negative = anti-predictive). Aggregate across a
  genome's projections by mean, best, or use-weighted (§8).

### 6.1 Scoring a FAN (K>1) — proper distributional skill, degenerating to point-IC at K=1

A multi-series projection is a *probabilistic* forecast, so it earns a *proper scoring rule*, not just
a point IC. The fan's empirical CDF at each bar is scored against the single realized `y_t`:

| metric | what it rewards | K=1 degeneracy |
|---|---|---|
| **CRPS** (Continuous Ranked Probability Score) | whole-distribution accuracy: calibrated AND sharp | reduces to MAE(point, y) |
| **Coverage error** | do ~90% of realized `y` land in the p05–p95 band? (PIT-histogram flatness) | undefined (band width 0) → skip |
| **Pinball / quantile loss** | per-quantile calibration (p50 unbiased, tails honest) | reduces to abs error at that quantile |
| **Sharpness \| calibration** | *narrow* bands that stay calibrated (a tight, honest fan is the prize) | n/a |

- **Default fan score = CRPS-skill** (1 − CRPS/CRPS_climatology), bounded, 0 = no better than a
  climatological fan, so it is directly comparable to the point rank-IC and combinable in §7. A fan
  that is merely wide (hedging) scores poorly on sharpness; a fan that is narrow but miscalibrated
  scores poorly on coverage — the metric forces *honest confidence*, which is exactly the property the
  policy's uncertainty-gated sizing (`spread`/`prob_up` in §3) needs to be able to trust.
- **The single implementation covers both:** compute CRPS/coverage/pinball over the `K` samples; at
  `K=1` these collapse to point error / IC, so `PSPoint` and `PSNoise` share one scorer. No branch on
  "is this a fan" — `K` just flows through.
- This is the per-strategy, *evolvable* cousin of `ProbabilityCloud`'s conformal-calibration fan and
  the mobile `ForwardBacktestTheater` p5–p95 band. Reuse those calibration utilities where they fit;
  keep the **target** purely realized-price-derived (§11 Q5) so the scorer never trusts a model.
- **Leakage guards (mandatory, non-negotiable):**
  1. Compare `p_t` only to values strictly after *t*. The last `H` bars have no target → excluded.
  2. **Purge + embargo** between the trade/fit window and the skill-measurement window (reuse the
     validation-rigor PIT oracle + purge/embargo machinery). A projection's *reported* skill is
     always the walk-forward **OOS** number, never in-sample.
  3. Skill is measured on the realized tape only; no simulator, no forward peeking, no `future` in
     any column the policy can read.
- **`FitnessResult` additions (optional, zero-impact):**
  ```haxe
  public var projScore:Null<Float>;          // aggregate OOS skill
  public var projScores:Null<Array<Float>>;  // per-projection, aligned to g.projections
  ```
  Existing callers that read only `.sharpe` are untouched.

---

## 7. Fitness combination — MAP-Elites is the co-evolution engine (DECIDED 2026-07-27)

**Decision:** the projection/manager pair is selected by **MAP-Elites, with forecast skill as a
behavioral-descriptor axis** — *not* by a weighted fitness scalar. Quality within a cell stays the
robust trading fitness we already use; forecast skill decides *which niche a genome occupies*, so the
archive holds the best trader *for each forecasting profile*. That is the "co-evolve pairs" story with
the repo's honest-diversity discipline intact, and it needs no magic weight to hand-tune.

**How it grounds into the existing `MapElites`:**
- Today's descriptor is `fills`-derived — `tradesPerBar` / `avgHold` / `longFrac` / `dutyCycle` —
  binned classically (`cellKey`, 4×4×3 = 48) *or* as unit-cube axes for the CVT centroid archive
  (`--cvt-cells N`). **CVT is the insertion point**: it already adds axes without bin-count explosion,
  which is exactly what we need.
- **Add forecast axes to the descriptor-v2 unit-cube vector:** `projSkill` (the OOS rank-IC / CRPS-skill
  from §6, normalized to [0,1]), and optionally `horizon` and `ProjKind` as coarse axes. Nearest-centroid
  over `(trades, hold, bias, dutyCycle, projSkill, …)` handles the higher dimension natively — no
  48→48×S blow-up.
- **Persist raw `projSkill` in the `FillDescriptor`-style record** (the cheap unbinned floats `EvoCache`
  already carries per genome) so warm-started genomes re-bin for free under a later run's thresholds —
  same pattern `describeFills` set up for the behavioral stats.
- `offer(genome, fitness, cellKey, …)` semantics are unchanged: best trading fitness wins each cell.
  Classic-mode users get a projection-skill bin appended to `cellKey`; CVT users get the extra axis.

**Cost realism unchanged:** turnover/slippage still charged (`OrderSim`), so a forecast that only wins
gross is still a net NO-GO.

**Explicitly deferred (not built first):**
- **`--proj-weight w` additive scalar** (`fitness = tradingScore + w·projScore`) — kept ONLY as a
  cheap P3 **smoke knob** to confirm projections move the needle before the descriptor wiring; never
  the selection path. It collapses two objectives and can farm `projScore` without trading — that's why
  it is not the engine.
- **Gated / curriculum** (unlock a projection's use once OOS skill clears a floor) — a good later
  composable on top of MAP-Elites; out of scope for the first cut.
- **Lexicase** (projection-skill-per-window as cases) — noted as an alternative for single-tape runs;
  not the default.

---

## 8. Variation & co-evolution mechanics

**v1 — intra-genome two-module co-evolution (do this first).**
One genome carries *both* the projection subtrees and the policy subtrees; they co-adapt under one
selection process.
- Extend `Variation`'s catalog so projection subtrees are mutation/crossover sites alongside the
  entry/exit/size trees. Two nested surfaces per projection: (a) the **sampler structure** — the
  `base`/`vol` `SeriesNode`/`ScalarNode` trees (existing machinery already mutates these), plus
  discrete moves on `NoiseModel`, `samples` (K, bounded), and `seed`; and (b) the **policy's fan
  references** (`SProj(name, field)` — mutate which reduction the policy reads, e.g. p50 → prob_up).
  Evolving `K`/`NoiseModel`/`vol` is how the engine searches *fan shape* (a tight gaussian vs a wide
  bootstrapped fan); evolving the read-field is how the manager learns to consume confidence.
- Crossover can swap a projection between genomes, or rewire a policy to reference a different
  projection — the two module boundaries give crossover meaningful, semantically-distinct cut points.
- **Module-aware credit (the elegant part):** extend the attribution oracle with a
  **projection-ablation** — zero / mean-fill / shuffle a projection's column and re-score the policy.
  - Δfitness from ablating `proj_i` = how much the policy actually *uses* it → deposit to
    `NmaCreditBank` / `GrowthWeights` for that projection.
  - A projection with high standalone `projScore` but ~0 ablation-Δ is **skillful but unused** — no
    credit, prunable. A projection that is both used and skillful is protected (the load-bearing case).
  - This closes the loop: forecasts are selected for being *exploited*, not merely correct.

**v2 — cooperative coevolution, two populations (the epic).**
A projector population and a manager population, evaluated in pairs.
- Substrate already exists in spirit: `Archipelago` / `RivalryArena` / `Foundry` (see
  `CLAUDE_HANDOFF.md` §4). Managers draw projections from a co-evolving projector island; pairing via
  best-response / shared-fitness / Pareto tournament.
- Hard problems to solve before this ships: the **pairing & credit-assignment** problem (which
  manager's success credits which projector), evaluation cost (pairs multiply), and disengagement /
  Red-Queen dynamics (standard CCEA failure modes). Present as a second, gated phase — v1 delivers
  most of the value with far less risk.

---

## 9. Guardrails (the moat — non-negotiable)

- **Honest NO-GO ledger.** A projection's skill claim is banked only if it survives purge/embargo OOS
  in walk-forward. Overfit forecasters that don't transfer are logged NO-GO like everything else.
- **Sell rigor, not alpha.** The deliverable is *honest, measurable forecast skill co-evolved with a
  policy that provably uses it* — not "we predict the future." The ledger of honest NO-GOs is the
  product's credibility, and this feature must not become a leakage machine that manufactures fake GOs.
- **Parity discipline.** Every phase default-off; a projection-free genome is byte-identical; a
  dead-projection genome is score-identical. Same-seed A/B on every behavior-changing flag.
- **No lookahead, ever.** If a differential test shows a projection column reading `≥ t+1`, that is a
  P0 stop-ship bug, not a tuning issue.

---

## 10. Phasing (order-flexible, each gated + parity-checked)

- **P0 — bundle-shaped schema + rendering + parity.** Land the *full* `ProjectionDecl` (`sampler`,
  `samples K`, `seed`, `kind`, `horizon`), `ProjSampler`/`NoiseModel`/`ProjKind` enums, and
  `SProj(name, field)` — even though the only sampler wired is `PSPoint` (K=1). This is the whole
  point of the user directive: **the multi-series shape exists from day one so MC needs no migration.**
  `Expand` prelude `let`s + `project(name,field)` builtin; `Canonical` key/count arms; validity checks
  (dense names, valid field, DAG, no self/forward ref). *Prove:* projection-free genome byte-identical;
  dead-projection genome score-identical; `PSPoint` inline vs builtin identical.

  **✅ Landed 2026-07-27 (P0.a — types + genome slot, verified 64,180/64,180 tests green):**
  - Bundle-shaped types: `ProjKind`, `NoiseModel`, `ProjSampler` (`PSPoint`/`PSNoise`), `ProjectionDecl`
    (`musescript/evo/`) — the full multi-series shape, only `PSPoint` (K=1) exercised.
  - `StrategyGenome.projections:Array<ProjectionDecl>` (optional, default-absent = byte-identical).
  - `Variation.copyGenome` preserves it; `TestProjectionScaffold` pins that attaching a projection is
    **inert for `Expand` and `Canonical.structuralKey`** (neither reads it yet) — the parity contract a
    future eval-wiring change must move deliberately.

  **✅ Landed 2026-07-27 (P0.b — SProj + rendering + fallback, verified 64,188/64,188 tests green):**
  - `SeriesNode.SProj(name, field)` added; **all forced switch sites** handled (compiler-verified):
    `Canonical` digest/key/count/shapeVector (+`K_SPROJ`), `Expand.series` + `KSeries` arm,
    `GenomeFeatures`, `TreeSurgery` (collect + replace), `LearnedLibrary`, `Simplify`, `TestNmaFitness`,
    plus a defensive throw in `NmaBijection.seriesFromEnum`.
  - `Expand.expand` renders each **referenced** projection reduction as a strategy-body field
    (`proj_0__p50 = sma("close", 5)`, corpus field-style) before `onBar`; unreferenced projections
    emit nothing (P0.a inertness preserved). `PSPoint` reuses the scalar series renderer; `PSNoise`
    throws (P1.5).
  - `Fitness.evaluateNma` routes any genome with `projections` to the **`nma-unsupported`
    Expand→interp fallback** — runs correctly, never hits the `NmaBijection` throw.
  - **Proven behavior-equivalent:** a PSPoint projection read once trades bit-identically
    (ok/sharpe/trades) to inlining its series (`testPointProjectionTradesLikeInlinedSeries`).

  **⏳ Still owed (next slices):**
  - ~~**P1.5 — `PSNoise` MC sampler**~~ **✅ LANDED 2026-07-27** (see the P1.5 phase note below).
  - **P1 — columnar eval**: `ProjBundle`/`ProjectionProvider` + an NMA `SProj` column (add `NmaSProj`,
    mirror `NmaCanonical` byte-for-byte) so projection genomes stop taking the interp fallback.
  - **P2 — scoring**: leakage-free projection-skill fitness term (`FitnessResult.projScore`).
  - **Identity-rebuild preservation beyond `copyGenome`**: `Variation.compactParams`/`remapOffsets`
    (and **remap `KParam` refs inside `PSNoise.vol`**), `Simplify` (~268), `RivalryArena` (~325), NMA-path
    rebuilds — needed once operators actually *create/evolve* projections (none do yet → P0.b is safe).
- **P1 — columnar eval + `ProjectionProvider` + reductions.** `NmaEval` `SProj` arm; `ProjBundle` (1
  column for `PSPoint`, K for later); reduction table (`p50`/`spread`/`prob_up`/… — all aliasing the
  single column at K=1). Differential test NMA vs interp/JS on genomes that read projections.

  **✅ Landed 2026-08-03 (P1 lean — PSPoint via `ProjInline`, not a new `NmaKind`):**
  - `ProjInline.forNma` rewrites referenced `PSPoint` `SProj` → underlying `SeriesNode` (K=1 reductions
    all alias) so columnar NMA runs bit-identically to Expand without `NmaSProj` / schema migration.
  - Unreferenced projection decls strip cleanly; `PSHost` / `PSNoise` stay on Expand→decorate (Graal
    workers intentionally never host `PSHost` — decorate-once then pack columns like aux).
  - `Fitness.evaluateNma` uses the inline path; cache identity stays on the original genome key.
  - **Still owed for full P1:** native `NmaSProj` + `ProjBundle` reduction table for fans; decorate
    columns readable as NMA features without Expand for hosts.
- **P1.5 — MC sampler (`PSNoise`) + fan reductions. ✅ LANDED 2026-07-27 (verified 64,219/64,219 green).**
  Key realization: for a **location-scale** noise family the `K` seeded shocks are a render-time
  constant, so every fan reduction is **closed-form in `(base, vol)`** — `Expand` bakes the fan into
  pure MuseScript arithmetic (no runtime builtin, no cross-backend dispatch, exact not sampled).
  - `McFan.hx` — Park-Miller MINSTD (exact-in-double, target-safe) + Acklam inverse-normal →
    deterministic `NGaussian`/`NStudentT` shocks; `sortedCopy`/`quantile`/`mean` helpers. Unit-tested
    (determinism, quantile ordering, gaussian-centered, seed-sensitivity).
  - `Expand.projReductionExpr` renders `PSNoise`: `sample_i`/`p05..p95`/`mean` as `base + coefᵢ·vol`,
    `spread` as `(q95−q05)·vol`, `PSPoint.spread` as `0`. `prob_up` (non-linear count) and
    `NBlockBootstrap` (needs tape residuals) throw — **owed** (both need a runtime column/builtin).
  - **Fitness-cache correctness fix**: `Canonical` now digests the *definitions* of **referenced**
    projections (name/kind/horizon/samples/seed/sampler) — two genomes referencing the same `proj_0`
    with different seeds no longer collide; unreferenced projection defs stay inert (both pinned by test).
  - Proven: a `PSNoise` fan renders to closed-form arithmetic, parses, evaluates end-to-end, and is
    deterministic across passes.
  - **Owed next**: `prob_up` rendering (K-term count or a `<>`-fraction), `NStudentT` is generated but
    add explicit tests, and the `NBlockBootstrap` runtime path.
- **P2 — projection scoring. ✅ POINT SCORER + PURGED OOS LANDED.**
  `ProjectionScore.hx`: the projection's central forecast series `p_t` is built PIT-causally by
  `NmaFitness.seriesColumnOf`/`scalarColumnOf` (new public helpers that reuse the exact columnar
  indicator tier); the realized target `y_t` for `kind`/`horizon` is derived STRICTLY from later bars;
  skill = **rank-IC** (continuous kinds) or **directional accuracy** (`PDirection`), last `H` bars
  excluded. `FitnessResult.projScore`/`projScores` + `Fitness.projectionScore`/`attachProjectionScore`
  (opt-in, off the hot path). Tests: rank-IC perfect/inverse, directional perfect/anti, target shapes +
  last-H exclusion, a level forecast scores ≈1 on a trend (end-to-end through the column helper),
  wiring for referenced vs unreferenced. **Leakage guarantee:** future data is touched only in the
  scorer, never in the eval the policy consumes.
  - **✅ 2026-08-03 purged skill:** `ProjectionScore.purgedSkill` + `Fitness.projectionScorePurged`
    mask pairs to the López-de-Prado purge+embargo OOS window (`PurgeEmbargo`). MAP axis uses the
    purged number; full-tape `projectionScore` remains for smoke/debug.
  - **Owed on the scorer**: the **distributional** side for fans — CRPS-skill / coverage / pinball on
    `spread`/quantile fields (§6.1) — plus an explicit **future-peek rejection** test.
- **P3 — fitness combination. ✅ LIVE WIRING LANDED 2026-08-03.**
  - `MapElites.normSkill` / `behaviorVecWithSkill` / `assignCellWithSkill` (forecast skill as 5th CVT
    axis) — mechanism proven earlier.
  - **`CorpusEvoRun --proj-map-axis`**: niches by `Fitness.projectionScorePurged` on all offer sites
    (tape + compete paths). `--ew-host` defaults the axis ON. CVT auto-enables at 48 cells.
  - **Anti-pattern fixed:** `--proj-weight` defaults to **0 always** (smoke knob only when explicit);
    archive `offer` quality is **trading fitness only** — skill niches via cell assignment, never
    folded into elite comparison.
  - **Owed:** same-seed multi-seed JVM A/B before default-on for non-`--ew-host` runs (creditConc
    axis measurably hurt OOS historically).
- **P4 — module-aware credit. ✅ ABLATION API LANDED 2026-08-03.**
  - `ProjectionAblation`: rewrite `SProj(name,*)→SPrice("close")`, Δ = baseline−ablated trading
    sharpe, deposit to `NmaCreditBank` under `proj:name`; `useWeights` for use-weighted skill.
  - Live deposit behind `--proj-ablate` (capped 8/gen on MAP offers) → also
    `ProjectionAblation.applyBankToTuner` (`GrowthWeights.projRead`).
  - **Owed:** automatic use-weighted `projScore` aggregation; mean-fill / shuffle ablation modes.
    ~~Variation growth weights reading `proj:` bank keys~~ ✅ via `applyBankToTuner` + `pickProjNameByCredit`.
- **P5 — CCEA (epic).** Two-population co-evolution on Archipelago/Rivalry; pairing + credit design.

  **✅ Landed 2026-08-03 (P5 crisp vertical — two pops + coupled trading fitness):**
  - `CceaCoEvo.hx`: forecaster pop (`PSPoint` decls) × manager pop (policy reads `SProj`); sticky
    partners; `compose` → joint genome; **shared trading fitness** credited to both; purged
    `projSkill` recorded on forecasters for niche/telemetry only — **never** selection-additive.
  - `Variation.mutateProjectionSampler` / `mutateManagerPolicy` / `growableProjNames` + credit-biased
    `pickProjNameByCredit` / `wireProjRead`; `ProjectionAblation.applyBankToTuner` seeds
    `GrowthWeights.projRead` from `NmaCreditBank` `proj:` keys (P4→P5 loop).
  - CorpusEvoRun `--ccea` (`--ccea-gens` / `--ccea-f-pop` / `--ccea-m-pop`) runs `runMini` on the
    IS tape and exits. `--proj-ablate` deposits during CCEA when combined.
  - **Still deferred for full CCEA:** multi-partner best-response / Red-Queen disengagement,
    Archipelago demes dual to RivalryArena, Pareto pairing tournaments.

---

## Live vertical (how to run co-evo with skill axis)

```
# JVM corpus evo — MAP niches by purged forecast skill (recommended)
haxe build-corpus-evo.hxml && java -jar … --proj-map-axis [--ew-host] [--proj-ablate]

# Flags
#   --proj-map-axis     CVT 5th axis = purged OOS proj skill (NOT additive weight)
#   --no-proj-map-axis  disable when --ew-host would otherwise enable it
#   --proj-weight w     SMOKE ONLY — do not use as the selection story
#   --proj-ablate       deposit projection-ablation Δ to NmaCreditBank (+ GrowthWeights.projRead)
#   --ew-host           decorate→pack PSHost columns; forces threads=1; enables proj-map-axis
#   --ccea              P5 two-pop forecaster×manager mini-loop on IS tape, then exit
#   --ccea-gens N       CCEA generations (default 3)
#   --ccea-f-pop N      forecaster pop size (default 4)
#   --ccea-m-pop N      manager pop size (default 4)
```

**Still deferred:** `NBlockBootstrap` / `prob_up` Expand rendering; native `NmaSProj`/`ProjBundle`;
CRPS fan scoring; full CCEA Red-Queen / multi-partner; default-on A/B for skill axis on non-host runs.

---

## 11. Open decisions (recommendations included — flag where you disagree)

1. **Horizon: fixed set vs evolvable `H`?** *Rec:* start with a small fixed set `{1, 5, 20}` (bounds
   the search + leakage surface); make `H` evolvable in P3+ once scoring is trusted.
2. **How many projections per genome, and how many samples `K` per fan?** *Rec:* cap projections at
   2–3 and `K` at ~16 (a fan is `K` columns + reductions — cost is `projections × K`); parsimony-
   penalize both like node count. Start `PSNoise` at a fixed `K` (e.g. 8), make `K` evolvable in P3+
   once the cost/skill trade is measured. A 3-projection × 16-sample genome is 48 columns — gated.
3. **Default skill metric?** *Rec:* rank-IC for continuous kinds, directional accuracy for
   `PDirection`. (Mutual information is tempting but noisier to estimate on short tapes.)
4. ~~Fitness combination mode?~~ **DECIDED (2026-07-27):** MAP-Elites descriptor axis (§7). Additive
   `--proj-weight` = P3 smoke knob only; gated/curriculum + lexicase deferred.
5. **Reuse `ProbabilityCloud` / `ForwardSim` (mobile `ForwardBacktestTheater`, umarketsim prob cloud)
   as a projection *target generator*, or keep targets purely realized-price-derived?** *Rec:*
   realized-price targets only for scoring (honest, no model-in-the-loop); ProbabilityCloud can
   *consume* evolved projections downstream, not define their truth.

---

## 12. Why this is worth building

It turns the engine from "evolve a policy over fixed features" into "**co-evolve what to believe about
the future and how to act on it**," with the belief held to an honest, leakage-free skill bar and
credited only when the policy actually uses it. It composes with everything already here — columnar
eval, MAP-Elites niches, the attribution/credit machinery, the validation-rigor leakage layers — and
it stays on the honest side of the ledger: a forecaster earns its keep OOS or it's a NO-GO. The moat
isn't "we see the future"; it's "we can *measure and evolve* forecast skill and prove a policy
exploits it, without lying to ourselves about lookahead."

*Data boner: structurally firmed. 🍆📈*
