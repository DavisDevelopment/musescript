# Promote `indicators/ew` → `musescript/ew`

**Date:** 2026-07-27  
**This pass:** docs + stub types under `musescript/ew/`. Implementation remains in `musescript/indicators/ew/` until a dedicated move PR.

---

## Why promote

EW is no longer “just an indicator.” It is the first instance of forecasting/projection infra that:

1. Enforces a hard grammar,
2. Learns soft φ/guidelines,
3. Emits probabilistic clouds / invalidations,
4. Feeds co-evolved trade logic (evo forecasting owned by Claude).

Indicators stay the **streaming + GeomViz facade**; `musescript.ew` owns the engine.

---

## Target layout

```text
musescript/ew/
  README.md
  ARCHITECTURE.md
  BRAINSTORM_COEVOLVE.md
  PROMOTE_PLAN.md
  ForecastCloud.hx          # DONE (stub)
  EwForecastHost.hx         # DONE (stub)
  # AFTER MOVE:
  ImpulseRules.hx
  CorrectiveRules.hx
  EwGuidelines.hx
  EwPhiParams.hx
  EwHypothesis.hx
  EwInvalidation.hx
  EwLattice.hx
  EwProject.hx
  EwRatioTargets.hx
  MonoWave.hx
  DowTrendFilter.hx
  LatticeForecastHost.hx    # NEW adapter → EwForecastHost
  # later: McmcForecastHost.hx, grammar/, mcmc/

musescript/indicators/ew/   # PHASE 2: thin re-exports only
  ImpulseRules.hx → typedef / @:forward to musescript.ew.ImpulseRules
  …

musescript/indicators/lib/
  EwHypothesisIndicator.hx  # imports musescript.ew.*; still registered as indicator

musescript/indicators/ew/handbook/  # stay here OR move to musescript/ew/handbook/
  BRAINSTORM.md, FINETUNE.md, PROGRESS.md, ch*.md
```

Geom (`SwingGraph`, `SwingGraphStack`, SoftScores, GeomViz) stays under `indicators/geom` — shared substrate, not EW-specific.

---

## Phased move (keep registry green)

### Phase 0 — this commit

- [x] Create `musescript/ew/` with architecture + co-evolve docs
- [x] `ForecastCloud`, `EwForecastHost` (+ stub)
- [x] Handbook pointer to new docs
- [ ] No mass package rename yet (avoids breaking tests / offline CLI mid-flight)

### Phase 1 — adapter without move

- Add `musescript.ew.LatticeForecastHost` that **imports** `musescript.indicators.ew.*` and fills `ForecastCloud`.
- Tests under `musescript/tests/TestEwForecastHost.hx`.
- Claude can bind ProjectionProvider → this host.

### Phase 2 — mechanical package move

1. `git mv` `indicators/ew/*.hx` → `ew/` (not handbook unless desired).
2. Change `package musescript.indicators.ew` → `package musescript.ew`.
3. Fix imports across tests, `EwHypothesisIndicator`, `EwFinetuneExport`, `SoftScores` cast sites, offline CLI.
4. Leave `musescript/indicators/ew/` as **one-liner facades** for one release:

```haxe
package musescript.indicators.ew;
typedef EwLattice = musescript.ew.EwLattice;
// or: @:deprecated("use musescript.ew") …
```

5. Run `build-geom-ew-tests` / finetune smoke / indicator registry compile.

### Phase 3 — delete facades

- After dependents import `musescript.ew` directly, remove `indicators/ew` facades.
- Keep handbook under `ew/handbook/` or `indicators/ew/handbook/` with a single README link.

---

## Non-goals for the move PR

- Do not rewrite EvolutionEngine / Fitness / Variation (Claude).
- Do not implement full MCMC.
- Do not break GeomViz field contracts (`ForecastBand`, zones, pivot marks).
- Do not put MCMC on the indicator `update()` hot path.

---

## Dependency direction (after promote)

```text
harness.Bar / geom.Swing*
        ▲
        │
   musescript.ew  (rules, lattice, project, ForecastCloud, hosts)
        ▲
        │
   indicators.lib.EwHypothesisIndicator   (viz facade)
   evo ProjectionProvider (Claude)        (SProj columns)
   indicators.offline.EwFinetune*         (batch soft θ)
```

`ew` must not depend on `evo` or `indicators.lib`. SoftScores currently lives in geom and references `EwPhiParams` by cast — after move, prefer a clean import of `musescript.ew.EwPhiParams`.

---

## Checklist for the move PR author

- [ ] All `import musescript.indicators.ew` updated or facaded
- [ ] `IndicatorRegistry` still resolves `EwHypothesis`
- [ ] Tests: handbook patterns, degree nesting, phi finetune, invalidation
- [ ] `LatticeForecastHost` cloud matches prior GeomViz band within ε
- [ ] Docs: README status table flipped to “implementation here”
- [ ] No edits to EvolutionEngine forecasting beyond consuming `EwForecastHost`
