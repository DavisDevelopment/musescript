# Claude handoff — MuseScript geometry stack + parked NMA / class-strategy

**Date:** 2026-07-26  
**Repos:** `muse-script` (`kalshai/muse-lab/muse-script`) + Mederos (`kalshai/mobile`)  
**Audience:** next agent (Claude) picking up where Auto left off  
**Do not push** unless the user asks. Prefer focused theme commits; leave unrelated trees alone.

---

## 0. One-paragraph situation

We shipped a **geometry / Elliott-Wave / Fib / Gann / cycle** indicator substrate with **GeomViz** chart packs, wired as **toggleable Advanced-chart overlays** in Mederos (not just a demo gallery). That work is **committed** (local only) on both repos. Still **uncommitted** and intentionally parked: a large **NMA strangler/perf** slice, **class-shaped strategies** (`ClassStrategyLower`), and the whole **pinescript/** package. The user asked what’s left on NMA and class-strategy; this file is the full intent dump so you can continue without rediscovering context.

---

## 1. What already landed (committed, not pushed)

### muse-script (indicators / geom / ew)

Rough commit chain (newest last among geom work; check `git log` for exact SHAs):

- Geometry/EW indicator stack + GeomViz chart packs  
- Deeper EW soft scores + offline CPD/LPPL polish  
- FloatSeries `fromVector` zero-copy on JS + geom tests registered  
- ArcSet / RingBag packs; pattern swings → SwingGraph  
- Remaining pattern `SwingTracker`s → SwingGraph  
- CycleSeries / RibbonSeries capped GeomViz packs  
- `GrowableVec.setAt` + `commitLength` for bulk column fills  

**Tests that were green when last run:**
- `haxe build-geom-ew-tests.hxml` + `node build/js/tests-geom-ew.js` → **1160/1160**
- Do **not** assume full `build.hxml` / `TestMain` is clean — mixed uncommitted deps

### mobile (Mederos)

- GeomViz Canvas2D paint (levels, rays, zones, pivots, labels, forecast, arcs, rings, cycles, LPPL ribbon)  
- Status coding: **Confirmed=0 solid · Forming=1 dashed · Projected=2 dotted**  
- Live MuseRuntime bind (`glcharts/geom/live.js`) prefer live packs, synth fallback  
- Family packs `GEOM_FIB|HARMONIC|EW|GANN|CYCLES|RISK` **and** per-builtin overlays  
- Advanced `+ ind` Geometry section (toggle like RSI/EMA)  
- Classic picker: GEOM listed as Advanced-only (disabled)  
- Indicator Library “Add to chart” via `chartBridge` when Advanced panel mounted  

**View:** `cd mobile && npm run demo:dev` → Geometry stack slide; or Advanced chart → `+ ind` → Geometry.  
**Selftest:** `node src/glcharts/geom/geom.selftest.mjs` → last seen **42/42**.

### Binding contract

- Haxe: `musescript/indicators/geom/GeomViz.hx`, `CHART_BINDING.md`  
- JS: `mobile/src/glcharts/geom/contract.js`  
- Nested last-bar fields: `levels`, `rays?`, `zones?`, `pivots?`, `labels?`, `forecast?`, `arcs?`, `rings?`, `cycle?`, `ribbon?`  
- Keep legacy Fib scalar fields for port parity; GeomViz packs sit **alongside**

---

## 2. Architecture we committed to (do not regress)

```
SwingGraph + PivotStatus (Confirmed | Forming | Projected)
        ↓
RatioEngine (tables · project/retrace · cluster · log|linear)
        ↓
┌─────────────┬──────────────┬───────────────┐
│ EW lattice  │ Harmonics    │ Gann secular  │
│ + Fib*      │ PRZ          │ angles / So9  │
└─────────────┴──────────────┴───────────────┘
        ↓
Soft scores / ScaleValidityGate / SSA / LPPL (offline-ish)
        ↓
Mederos GeomViz paint (Advanced overlays)
```

**Laws:**
- Hot paths: `RingBuffer` / `FloatSeries` / `GrowableVec`, **indexed loops**, no `Array.shift` / `for..in` on JVM hot scans — see `musescript/evo/nma/JIT_AUTHORING_GUIDE.md`
- **One** RatioEngine / LevelCluster for Fib + harmonics + VP + Gann (adapters, not duplicate engines)
- Pivot-anchored Fib is **canonical**; trailing HH/LL = optional `mode=Window`
- Fourier stays its **own** family; SSA/MESE preferred as FibTimeZones successor
- Gann: explicit `pricePerBar` — no silent global scale
- LPPL = separate BubbleRisk channel, not inside EwProject
- **No** god-class `ElliottWave.hx`; **no** in-indicator LLM/DRL; AI stays offline
- **PARK:** astrology, Mesoamerican calendars, Cowan cycles, HLPPL media hype, RG/Lie god-stack

**Research that informed the plan** (user paths, already digested):
- `E:\theohgawd\From Subjectivity to Precision_ A Hybrid AI Architecture for Automated Elliott Wave Forecasting.md`
- `e:\theohgawd\From Gann to Chaos Theory_ A Taxonomy of Hidden Geometries in Market Analysis.md`
- `e:\theohgawd\From Heuristic to First Principles_ A Cross-Disciplinary Foundation for Proportional Analysis in Financial Markets.md`

---

## 3. Class-strategy — what’s left

### Intent

Authoring surface:

```muse
class RiskManaged extends muse.Strat {
  param stopPct: Scalar = 0.05
  function onPosition() { when unrealized_pnl_pct() < -stopPct: flat() }
}
class MaCrossover extends RiskManaged {
  function onBar() { when crossover(sma(close,8), sma(close,34)): long() }
}
```

**Lower at compile time** via `ClassStrategyLower` into ordinary `StrategyDecl` / `IndicatorDecl` so checker, emitters, WASM, and evo stay class-ignorant and stay on the **compiled** path (~70× vs interpreter class runtime with `EThis`/`ESuper`).

Roots: `muse.Strat`, `muse.Indicator` (`compute` entry for indicators).

### Already written (UNSTAGED)

| Piece | Path |
|---|---|
| Lowering pass | `musescript/compile/ClassStrategyLower.hx` (**untracked**) |
| Parser: dotted `extends`, `param` in class body | `musescript/parse/StrategyParser.hx` (modified) |
| Compile pipeline hook | `musescript/compile/MuseCompiler.hx` — `ClassStrategyLower.expand` **before** Template/Module |
| Public API | `musescript/MuseScript.hx` — `lower` + `plan` call ClassStrategyLower once each |
| Checker | `musescript/checker/MuseChecker.hx` — don’t warn on unknown parent for builtin roots |
| Tests | `musescript/tests/TestLangClassStrategy.hx` (**untracked**); wired in `TestMain.hx` |
| Example | `examples/strategy-kinds/90_class_strategy_inheritance.ms` (**untracked**) |

### Real gap (fix this)

**`MuseRuntime.parse`** (`musescript/runtime/MuseRuntime.hx`) still does:

```haxe
prog = TemplateExpand.expand(prog);
prog = ModuleExpand.expand(prog);
// MISSING: ClassStrategyLower.expand(prog)
```

Same class of gap may exist in `MuseDebugSession`, `GeneRunner`, `CorpusSeed`, etc. Grep for `TemplateExpand.expand` without a preceding `ClassStrategyLower`. Studio will not correctly load `class X extends muse.Strat` until Runtime is fixed.

### False alarm (ignore)

Earlier agents worried about “double expand” in `MuseScript.hx`. **Not a bug:** `lower`, `plan`, and `MuseCompiler.compileEx` each call ClassStrategyLower **once** on their own path.

### Suggested class-strategy finish order

1. Grep all parse/lower entry points; add `ClassStrategyLower.expand` where Template/Module run  
2. Run `TestLangClassStrategy` (+ smoke example `90_...ms`)  
3. Commit **one focused theme**: class-strategy lower + parser + checker + tests + example  
4. Do **not** bundle with NMA or pinescript  

---

## 4. NMA — what’s left

### Intent

Columnar NMA is the **strangler** for evo fitness: when `Fitness.preferNma` (CorpusEvo `--nma`), evaluate genomes on unboxed columns instead of Expand→compile→run every time. Fallback remains for unsupported shapes. JIT doctrine lives in `musescript/evo/nma/JIT_AUTHORING_GUIDE.md` — treat it as law on hot paths.

### Unstaged cluster (big, intertwined)

**Modified (among others):**
- `nma/`: EngineIndicatorProvider, NmaAttr, NmaBijection, NmaCanonical, NmaColumnCache, NmaCreditBank, NmaEpoch, NmaEval, NmaEvalContext, NmaFeatureHost, NmaFitness, NmaFuseHost, NmaNode, NmaPositionEval, NmaSignalPack, NmaSignalProbe, JIT_AUTHORING_GUIDE.md  
- `evo/`: Fitness, Variation, EvolutionEngine, Canonical, StructuralDigest, PhaseTimer, …  
- Tests: TestNmaStrangler, TestNmaEval, TestNmaDeep, TestMain, …

**New untracked:**
- `NmaBarColumns.hx` — hoist OHLC+index out of boxed `Bar` field reads (JFR-motivated debox)  
- `NmaPaletteColumns.hx`  
- `NmaSignalMemo.hx` + `NmaSignalMemoEntry.hx` — gen-scoped signal→fitness memo + single-flight  
- Also nearby unstaged evo: `Archipelago.hx`, `RivalryArena.hx`, `Foundry.hx`, `IntPairList/Map`, `FitnessOpts`, `NmaNodeBench`, `NmaNodeEvalPool`, …

**Already committed (related):** `GrowableVec.setAt` / `commitLength` (`dd3e0d7`) — needed for bulk column fills; don’t redo.

### Themes inside the unstaged NMA work

1. **Debox tape** — `NmaBarColumns` / FloatSeries columns; kill per-bar boxed `Bar.close` on JVM  
2. **Signal memo** — content-address OrderSim inputs; single-flight under threads; clear each gen with pop memo  
3. **Attribution cost control** — `Fitness.attrMaxCold`, `attrBankFill`; credit bank deposits  
4. **Verify hygiene** — `--nma-verify` must **not throw** from pool workers (hangs barrier); count mismatches / compiled failures instead  
5. **Eval / fitness / feature host** — substantial logic deltas; read diffs carefully before committing  

### Known intentional holes (do not “fix” without a plan)

| Hole | Behavior |
|---|---|
| `KFeature` / nested-source `SInd` | `backend == "nma-unsupported"` → Expand→compile fallback |
| Full MF-DFA / PELT in indicators | Stubs in `ScaleValidityGate` / offline hooks — low leverage vs NMA commit |
| `SymbolSelector` shared hyper-opt vector | Explicit TODO; FloatSeries/GrowableVec are the direction, not done for SymbolSelector |
| Foundry consensus | Stub hybrid inject only |
| CorpusEvo `--compete` / Murmuration Phase 2 | Not implemented (comments in CorpusEvoRun) |

### Suggested NMA finish order

1. **Diff-read** Fitness + NmaFitness + NmaEval + NmaSignalMemo + NmaBarColumns as one story  
2. Run strangler / NMA tests: `TestNmaStrangler`, `TestNmaEval`, `TestNmaBarColumns` if present, IntPair* if committing those  
3. Commit **NMA debox+memo+attr** as one PR/theme — pull **only** the evo files that won’t compile without (Fitness, Variation, EvolutionEngine, IntPairMap if SignalMemo needs it, …)  
4. Leave **Foundry / Rivalry / Archipelago** for a **second** commit if they’re not required to compile the NMA slice  
5. Optional later epic: extend columnar coverage past `KFeature` (real work, not a drive-by)

### NMA commit hygiene

- No `build/*.jfr`, bench txt dumps, wasm artifacts  
- No amend of geometry commits  
- Message should say **why** (debox / memo / verify-nonthrow / attr caps), not list every file  

---

## 5. Also still unstaged (out of scope unless user asks)

| Tree | Notes |
|---|---|
| `musescript/pinescript/` + `pine*.hxml` | Whole Pine→Muse pipeline; not smoke-verified in the geometry session |
| Class-strategy | See §3 — **do** finish if continuing language work |
| NMA + rivalry/foundry | See §4 |
| `ALGORITHM_AUDIT.md`, `NPM_PACKAGE_PLAN.md`, `PIP_PACKAGE_PLAN.md`, `polishpass_notes.md` | Docs/plans; commit only if user wants |
| README.md, ConstFold, JsEmitter, OrderSim, OrderBook, BuiltinSigs, … | Mixed drive-bys — don’t sweep into NMA/class commits without reading |

---

## 6. User preferences (from this chat)

- Wants **toggleable chart overlays** (Advanced `+ ind`), not gallery-only — **done**  
- Wanted commits, then leftovers, then re-audit — **done** for geom  
- Explicitly asked for this handoff file for Claude  
- Flirty/casual tone OK in chat; keep **code/commits professional**  
- “Every inch” of the geom plan was the mandate; NMA/class were parked for cleanliness  
- Prefer re-evaluate before boiling oceans (legacy `Array.shift` across all of `lib/` is a long tail — only touch files you migrate)

---

## 7. Quick commands

```bash
# muse-script — geom tests
haxe build-geom-ew-tests.hxml && node build/js/tests-geom-ew.js

# muse-script — status of parked work
git status --short musescript/compile/ClassStrategyLower.hx musescript/evo/nma musescript/tests/TestLangClassStrategy.hx

# mobile — geom selftest
cd ../mobile   # or C:\Users\epiki\Documents\Development\kalshai\mobile
node src/glcharts/geom/geom.selftest.mjs
npm run demo:dev   # Geometry stack / Advanced + ind
```

---

## 8. Recommended next moves (opinionated)

**If language UX first:** finish class-strategy Runtime wiring → tests → commit. Small, coherent, user-visible.

**If evo perf first:** land NMA BarColumns + SignalMemo + Fitness verify/attr knobs with minimal interdependent set → strangler tests → commit. Leave Rivalry/Foundry for later.

**If packaging/docs:** ignore until user asks; pinescript is its own project.

**Do not:** reopen PARK mysticism; rewrite Fib as trailing-window-canonical; put LLM in `MuseIndicator.update`; amend already-pushed commits (nothing was pushed from this session’s geom work — still don’t amend unless user explicitly wants amend *and* amend rules allow).

---

## 9. Open questions you may ask the user

1. Class-strategy first, or NMA first?  
2. Should MuseRuntime / Studio be the gate for class-strategy “done”?  
3. Commit Rivalry/Archipelago/Foundry with NMA or strictly separate?  
4. Touch pinescript this pass or leave forever-parked until a Pine epic?  
5. Push + PR for geom commits on muse-script and mobile?

---

*End of handoff. Prefer this file over re-deriving intent from agent transcripts.*
