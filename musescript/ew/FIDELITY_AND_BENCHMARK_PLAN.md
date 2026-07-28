# EW fidelity + real MCMC + benchmark plan

**Date:** 2026-07-27
**Author:** evaluation pass over the existing `musescript.ew` / `indicators.ew` subsystem.
**Goal (user):** a *full, faithful* Elliott Wave implementation on top of a *sound fitting +
MCMC model* that computes, at once, **all** rule-valid EW interpretations of an input **and**,
for each, the **full list** of price-action predictions — then **benchmark** it with real numbers.

Handbook of record: `~/Downloads/elliott-wave-principle.pdf` (Frost & Prechter).
Framework paper: `theohgawd/Navigating Ambiguity in Elliott Wave Analysis… (Hierarchical MCMC).{md,pdf}`.
Companion: `theohgawd/From Subjectivity to Precision — Hybrid AI Architecture for Automated EW.md`.

---

## 1. What we already have (and it's good)

The deterministic skeleton the paper calls "hard grammar + soft params + discrete search +
prediction/UQ" is **mostly built and tested**. Concretely:

| Paper layer | Status | Where |
|-------------|--------|-------|
| Hard grammar — motive/impulse/diagonal (trunc/ext), zigzag, flat×3, triangle×2, double-zigzag, double-three | **DONE, hard-gated, non-learnable** | `ImpulseRules`, `CorrectiveRules` |
| Soft/learnable θ — φ family, tolerances, guideline weights, wave-target tables | **DONE**, finetune-loadable | `EwPhiParams` (+ `offline/PhiParamsDump`) |
| Guidelines — alternation, equality 1&5, depth-to-4th, channel proxy | **DONE (partial)** | `EwGuidelines` |
| Discrete search — multi-window top-K lattice (4/6/8 pivots) | **DONE** | `EwLattice` |
| Degree nesting | **2-level only** (fine/coarse via `SwingGraphStack`) | `EwLattice.rebuildStack` |
| Prediction — wave-aware Fibonacci bands + time | **DONE** | `EwProject`, `EwRatioTargets` |
| Invalidation levels | **DONE** | `EwInvalidation` |
| UQ scalars — entropy over top-K, nest score, dist-to-invalidation | **DONE** | `LatticeForecastHost` |
| Forecast surface / host interface | **DONE** | `ForecastCloud`, `EwForecastHost`, `LatticeForecastHost` |
| Evo boundary X — host→provider→`SProj`→fitness, PIT-causal | **DONE (lattice path)** | `ProjectionProvider`, `PSHost`, `ProjectionScore` |
| Forecast-skill scoring — rank-IC, directional, band coverage, hit-rate (leakage-free) | **DONE** | `evo/ProjectionScore.hx` |
| Demos | **DONE** | `HostProjectionCli` (headless), `HostProjectionDemo` (JVM GUI) |
| Tests | Ch1–4, patterns-A, degree-nesting, host-projection smoke | `tests/TestEw*` |

**Bottom line:** the *deterministic* engine is solid, honestly PIT-disciplined, and already
wired into evolution. The keeper is that hard rules never read learnable floats — that
invariant must survive everything below.

---

## 2. The real gaps vs. the stated goal

Four gaps separate "good top-K lattice" from "faithful theory + sound MCMC + real numbers."

### G1 — There is no real MCMC (the headline gap)
`McmcForecastHost` is honestly labelled "pragmatic": it multinomial-resamples the **already-valid,
already-ranked top-K≤8** lattice rivals with mass ∝ soft score, then aggregates their bands. That
is **importance resampling of a fixed candidate set**, not a Markov chain. Missing vs. the paper:

- **No proposal kernel** over labelings (swap flat↔zigzag, split/merge a sub-wave, re-degree a
  pivot, shift a boundary) — the grammar-preserving moves the paper's §"Inference Engine" requires.
- **No acceptance ratio / detailed balance** — so the "posterior mass" is just normalized soft
  score over ≤8 hand-enumerated windows, not mass over the combinatorial space.
- **No outer θ chain** — soft params are a single fixed pack (or an evo gene delta), never sampled
  jointly with labelings. The paper's two-stage hierarchical MH (outer θ, inner L|θ) is absent.
- **Bounded enumeration** — `MAX_K = 8`, windows of exactly 4/6/8 pivots. "All interpretations at
  once" is currently "up to 8 fixed-width windows," which under-counts real ambiguity.

### G2 — Fractal recursion is only 2 levels deep
Faithful EW is recursively self-similar: W3 of an impulse is itself a 5-wave of lower degree, whose
W3 is again a 5-wave, etc. Today `SwingGraphStack` has exactly **fine + coarse** (2 ZigZag
thresholds) and `nestingSoft` links one child to one coarse parent. There is **no recursive parse**
that validates a labeling's internal sub-structure. So "full fractal 5+3 across degrees" is not yet
faithful — it's a 2-degree soft overlay. (`BRAINSTORM.md` C9/C10 flag this as PLANNED.)

### G3 — Theory coverage still has honest holes
- Channeling is a linearity *proxy*; **throw-over** weight exists but is thinly used.
- **No volume-confirmation guideline** (paper explicitly wants volume as a soft prior).
- **No wave-personality** guideline set (Ch2 of the handbook).
- Triangles: contracting/expanding present; **barrier/running** and full a-b-c-d-e maturation partial.
- Combinations: double only; **triple three / triple zigzag** and the full W-X-Y-X-Z connector
  grammar absent.
- **Fibonacci time** is simple multiples; no time-cluster confluence.
- **CPD regime priors** and an MF-DFA-style `ScaleValidityGate` are PLANNED (D12/D13).

### G4 — There is no benchmark that answers the five questions
This is the biggest *product* gap. What exists (`ProjectionScore`) is a **fitness signal** — a single
aggregate rank-IC / hit-rate / coverage number, computed inside evolution, on one synthetic tape in
the CLI. It does **not** answer, on real tapes, over many anchors:

1. Did **any** projection path capture the realized price action? *(best-of-fan hit, not mean IC)*
2. Within **what margin of error**? *(distribution of min-distance realized↔nearest band)*
3. **How often** on average? *(hit-rate across a real (symbol,t) anchor grid)*
4. How much does **fitting** improve it? *(handbook-default θ vs finetuned/MCMC-posterior θ, A/B)*
5. How much **profit** is realistically extractable? *(honest cost-charged PnL from the edge)*

Also missing: **CRPS** (proper score the paper names) — only meaningful once samples>1 from a real
posterior — and a **per-interpretation** output (all counts × each count's full prediction fan),
because today the host aggregates rivals into one reduced cloud.

---

## 3. Plan — four phases, each independently landable & benchmarkable

Ordering rule: **build the benchmark first (Phase 0)** so every later phase reports a number, not a
vibe. Then enumeration, then real MCMC, then fidelity — each measured against Phase 0.

### Phase 0 — Benchmark harness (do this first)
Deliver a standalone, offline, PIT-causal harness that scores the *existing* lattice/pragmatic-MCMC
host on **real tapes** and answers all five questions. Everything after is measured against this.

- **0.1 `ForecastEnsemble` surface.** Add a per-interpretation output beside `ForecastCloud`:
  `Array<{ labeling, degree, posteriorMass, fan:Array<EwProjectBand>, invalidation }>`. The cloud
  stays the reduced consumer view; the ensemble is what the benchmark and "all predictions for each
  interpretation" need. Cheap: the host already computes per-hyp bands, it just discards them.
- **0.2 Anchor grid + targets (leakage-free).** Reuse `ProjectionScore.realizedTarget` discipline:
  at each anchor bar `t` on a held tape, freeze the ensemble from data ≤ t; realized path = bars > t
  out to horizon `H`. No future ever touches the labeling.
- **0.3 Metrics (the five answers), pure + unit-tested:**
  - **Q1 any-path capture:** `anyHit = ∃ band in fan s.t. realized path enters [priceLo,priceHi]
    within [barLo,barHi]`. Report per-anchor and % of anchors.
  - **Q2 margin of error:** min over fan of normalized distance `|realized − nearest band edge| /
    ATR` (and in ticks / %). Report the distribution (p50/p90), not just a mean.
  - **Q3 frequency:** Q1 aggregated over the whole anchor grid, sliced by pattern label, degree,
    horizon, and regime.
  - **Q4 fitting lift:** run the whole grid twice — handbook-default θ vs finetuned/posterior θ —
    and report Δ(anyHit%), Δ(margin), Δ(CRPS). This *is* "how much does fitting help."
  - **Q5 profit:** a thin, honest strategy that trades the ensemble (e.g. enter toward preferred
    fan when `distToInvalidation` is wide + entropy low; stop at invalidation) run through the
    existing `BacktestEngine` with **real turnover costs** (see `turnover-cost-bug-2026-07` memo —
    charge honestly). Report net Sharpe / equity after costs, and the null (buy-hold / random-fan).
  - Add **CRPS** now as a stub over the fan (degenerates to MAE at samples=1) so Phase 2 lights it up.
- **0.4 Runner + report.** `EwBenchmarkCli` (Node/sys): `--tape <csv> --horizon N --anchors …`
  → prints a numbers table + writes JSON/CSV to the run ledger (`run-visibility-directives` memo:
  every run leaves a reproducible trail; log negatives equally). Reuse a real held tape
  (`corpus/tapes/spy_oos_*.csv`, and the equities/crypto DBs).
- **Gate:** honest baseline numbers for today's engine on ≥1 real tape, with NO-GO reported plainly
  if the lattice doesn't beat the null. (Consistent with the ledger-honesty moat.)

### Phase 1 — Enumeration breadth ("all interpretations at once")
Make the candidate set an honest census, not a fixed top-8.

- **1.1 Widen/parametrize lattice** beyond `MAX_K=8` and fixed 4/6/8 windows; sampler budget as a
  cap, not a hard 8. Keep JIT discipline (indexed loops, no `Array.shift`).
- **1.2 Recursive candidate generation (bounded):** allow a labeling's actionary sub-wave to carry
  a lower-degree 5/3 candidate — the substrate real MCMC will move over. Depth-capped for cost.
- **1.3 Report** enumeration coverage vs. a brute-force reference on short synthetic series (how
  much of the true valid set do we enumerate?). This validates that the posterior later has support.

### Phase 2 — Real hierarchical MCMC (the "sound fitting + model")
Replace pragmatic resampling with a genuine chain. Same `EwForecastHost` API so evo/benchmark are
untouched at the boundary.

- **2.1 Validator as acceptance gate.** Keep `ImpulseRules`/`CorrectiveRules` as the O(1) boolean
  gate; optionally add a CYK-style parser for recursive validity (paper §grammar) so nested
  labelings are checkable in O(n³). The gate guarantees the chain never leaves valid structure.
- **2.2 Inner MH over L | θ.** Grammar-preserving proposal kernel: {swap corrective form, split/
  merge sub-wave, re-degree pivot, nudge boundary}. Likelihood = weighted guideline violations
  (Harmonic-Grammar-style: valid=0 base, penalty ∝ soft miss × learned weight). Accept via MH ratio.
- **2.3 Outer MH over θ** (`EwPhiParams`-shaped, positive-clamped tolerances). Two-stage hierarchical
  sampler = coordinate ascent between θ and L, exactly the paper's structure.
- **2.4 Posterior synthesis.** Aggregate accepted (L,θ): predictive bands (real p05–p95, not φ-span),
  invalidation distribution, entropy/nest/dist-to-inv from **actual sample frequencies**. Now CRPS is
  real. `samples` = accepted draws.
- **2.5 Cost governance** (`ARCHITECTURE.md` risks): lattice host stays the population-eval default;
  MCMC runs elite-only / offline / on the benchmark. Gene-capped `samplerBudget`, fixed seed for
  reproducibility. CPU-only budget respected (`compute-budget-cpu` memo).
- **Gate:** Phase-0 numbers must **improve** (CRPS↓, anyHit%↑, or margin↓) vs. the lattice baseline,
  net of cost — else report NO-GO and keep lattice.

### Phase 3 — Theory fidelity completion
Close G2/G3 so "faithful" is literally true. Each item is soft-only unless it's a genuine hard rule.

- **3.1 Recursive degrees** (C9): N-threshold `SwingGraphStack` + true parent-child validation of
  internal sub-structure (a labeling is only "clean" if its W1/3/5 parse as lower-degree motives).
- **3.2 Guidelines:** real channeling (parallel-channel fit), throw-over, **volume confirmation**,
  **wave personality**, alternation enforced at the posterior (not just per-count soft).
- **3.3 Corrective completion:** barrier/running triangles, triple three/zigzag, full W-X-Y-X-Z.
- **3.4 Time:** Fibonacci time clusters / confluence, not just leg multiples.
- **3.5 Regime priors:** CPD flags (D12) + `ScaleValidityGate` (D13, MF-DFA-ish) reweight labels —
  soft priors only, never hard gates.
- **3.6 Calendar degree naming** (Grand Supercycle → Subminuette) for product/UI.
- **Gate:** every addition re-runs Phase 0; keep only what moves a number.

---

## 4. Invariants (do not break)

- Hard structural rules **never** read learnable floats for boolean gates. Ever.
- PIT discipline: labelings/forecasts built from data ≤ t; targets strictly > t; the only place
  future data appears is the benchmark's realized-path scorer.
- Honest costs in Q5 (turnover-cost bug memo). Report NO-GOs as loudly as GOs (ledger is the moat).
- JIT hot path clean (indexed loops, no `Array.shift`); MCMC never inside `MuseIndicator.update()`.
- Don't fork the evo-owned files (`EvolutionEngine`/`Fitness`/`Variation`/`StrategyGenome`); integrate
  at boundary X. `ProjectionScore` is the reusable scorer — the benchmark shares its target logic.
- Never treat a Projected band as Confirmed; forming vs confirmed pivots stay distinct.

## 5. Suggested first move

Phase 0.1–0.4 on one real held tape (`spy_oos`), reusing `EwProject.fromHypothesis` per-hyp bands +
`ProjectionScore.realizedTarget`, emitting the five-question table. That gives an honest baseline for
today's lattice **before** any MCMC work — and tells us whether EW clears the null at all, which
governs how much to invest in Phases 2–3.
