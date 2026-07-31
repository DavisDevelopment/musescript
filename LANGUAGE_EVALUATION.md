# MuseScript — language evaluation: metaprogramming, expressiveness, optimization, speed

**Date:** 2026-07-31. A grounded survey of where the language has real headroom, with
Haxe / stack-VM inspiration. Framing first, because it's earned: **MuseScript is already a
remarkably complete language** — first-class functions + closures, pattern matching (`EMatch`),
generators/coroutines (`EYield`/`EYieldStar` + a full lazy-iterator runtime), enums + classes,
a real metaprogramming layer (macro / module / template), a nascent type system
(`Series/Scalar/Bool/Window/Price`), 6 backends (interp / JS / WASM / Haxe / Py-Numba / Math) at
**byte-identical parity**, and a genuine optimizer (SeriesLowering, StaticInline, ConstFold, CSE,
TailCallPass, GeneratorLower, NMA WASM-fusion). The recommendations below are specific levers on a
strong base, not a rewrite.

Ranking legend: **impact** (▲ high / ◆ med) · **effort** (S/M/L).

---

## Axis 1 — Metaprogramming & the templating/holes system

Two "hole" systems exist and are **disconnected**: compile-time author templates
(`macro`/`module`/`template` → `TemplateExpand`/`ModuleExpand`) and evolutionary synthesis holes
(`BHole`/`KHole` in the evo AST, filled by `Variation`). Bridging them is the biggest opportunity.

**1.1 — Full macro hygiene** ▲ · M
*Current:* `TemplateExpand.substitute` is *shadow-aware* (saves/restores env when a local binding
shadows a param) but **not fully hygienic** — bindings *introduced by* a template/module/macro body
are not freshened, so inlining a body with `let tmp = …` can capture/collide with a call-site
`tmp` (or vice-versa). `ModuleExpand` validates params but also doesn't rename body locals.
*Improvement:* gensym body-introduced bindings on expansion (alpha-rename to fresh names), or at
minimum detect-and-error on capture. *Haxe:* macro reification (`macro`/`$v{}`) + `Context` mint
hygienic temporaries. *Why it matters:* silent variable capture makes the compiler quietly change
what your code *means* — a direct violation of the honesty invariant ("never lie, including about
your code"). **Correctness first.**

**1.2 — Author-writable holes, filled by the honest engine** ▲ · L — *the standout*
*Current:* holes are internal to synthesis; authors can't write one. *Improvement:* a source-level
hole — `?` (untyped) or `?Scalar in [0,100]` / `?Bool` / `?Series` (typed + domain-constrained) —
that lowers to `KHole/BHole/SHole` so the evolutionary engine fills it under the honest gate.
*"Write a strategy sketch, let the engine evolve the holes — and tell you honestly if what it
found is real."* This unifies metaprogramming ↔ synthesis and is a **killer product feature**: the
language itself becomes the customization surface, the engine the fill mechanism, the instrument
the honest judge. Ties straight to the constitution's efficacy/customization thesis.

**1.3 — A SERIES hole (`SHole`) + domain-typed holes** ▲ · M
*Current:* only `BHole` (bool) and `KHole` (scalar) — evolution can't leave *which indicator/series*
as a hole, and holes carry no domain/type constraint (they just wrap an inner node). *Improvement:*
add `SHole` (series), and let holes carry a type + domain (`Scalar in [0,1]`, `Bool = a cross`),
so search is guided instead of blind. Faster, saner synthesis; also the substrate for 1.2's typed
author holes. *(Feeds directly off Axis-2 abstract types.)*

**1.4 — Consolidate the three statement-expanders** ◆ · M
*Current:* `macro` (0 params) vs `StmtTemplateDecl` (typed params) vs `module` (params+defaults+
`use`) are three overlapping ways to expand a statement body. *Improvement:* collapse toward one
model — `macro` = a 0-arg template; `module` = a template with `use` composition semantics —
reducing language surface + teaching burden. *Haxe:* one macro system + `@:build`, not three. At
minimum, document the distinction crisply; ideally unify.

**1.5 — Fill out the existing TODOs** ◆ · S–M
- **Bounded recursive templates** (the explicit `TemplateExpand` TODO; `MAX_DEPTH=64` already there) —
  unlocks generative structure (build an N-deep pattern). Terminating-recursion guard.
- **Template default args + optional types** — modules have both; templates require typed params.
  Close the asymmetry.
- **Class inheritance (P3)** — `parent` is parsed but unused.

**1.6 — Compile-time reflection / staged metaprogramming** ◆ · L
Iterate an enum's variants or a param list at expand time (e.g., "for each symbol in the universe,
emit this rule"). *Haxe:* `@:build` macros construct fields from types. Enables truly generic
strategies without copy-paste.

---

## Axis 2 — Expressiveness (Haxe-inspired, mostly zero-cost)

**2.1 — Zero-cost abstract / unit types** ▲ · M — *top expressiveness pick*
*Current:* the type system already distinguishes `Price` from `Scalar` (nominal, coarse).
*Improvement:* promote these to real **Haxe-style `abstract` types** — type-safe wrappers with
*no runtime cost* and operator rules: `abstract Price(Float)`, `abstract Bps(Float)`,
`abstract Percent(Float)`, `abstract Bars(Int)`. Now `price + bars` is a **compile error**, and
`stop = entry * 0.98` vs `stop = entry - 2%` can't be silently confused. Catches unit bugs at
compile time (the most common, most expensive silent strategy bug) at zero runtime cost — pure
honesty dividend. *Haxe:* `abstract` + `@:op`. Also the natural home for domain-constrained holes
(1.3).

**2.2 — Static extensions (`using`)** ◆ · S
*Haxe `using`:* `series.sma(5).crossesOver(price)` reads far better than nested calls, with zero
cost (compiles to plain function calls). Big ergonomic win for a fluent indicator DSL; strengthens
the "peek the math / forkable indicator" story.

**2.3 — A pipe operator `|>`** ◆ · S
The runtime already has lazy iterators (map/filter/scan/zip/…); `bars |> sma(5) |> zscore |> clamp`
makes pipelines first-class and readable. Pairs with 2.2.

**2.4 — Exhaustiveness + purity annotations** ◆ · S–M
- **Exhaustive `match`** warnings (Haxe warns on unmatched enum variants) — catch a missing regime
  case at compile time.
- **`@:pure`** on indicator/fn decls — a purity marker lets the optimizer hoist/CSE/memoize safely
  and aggressively (Axis 3), and is checkable. Cheap annotation, compounding optimization payoff.

**2.5 — Refinement / range types** ◆ · M
`param len: Scalar in 2..200` — documents intent, guards user input, *and* becomes the search
domain for a hole (1.3). One annotation, three payoffs (docs, validation, synthesis).

---

## Axis 3 — Optimization (compile-time)

*(The pipeline already re-runs ConstFold + CSE **after** expansion, has SeriesLowering/SeriesLiveness,
StaticInline, TailCall, and NMA WASM-fusion — so these build on real machinery.)*

**3.1 — General stream/iterator fusion** ▲ · M
*Current:* NMA has a *specific* fused WASM emitter; the **general** lazy-iterator pipeline
(`map.filter.scan.zip`) still allocates an intermediate `MuseIter` per stage. *Improvement:*
stream-fuse chained iterators into a single loop with no intermediate allocation (classic
GHC/Haxe stream fusion). Big win for the fluent-pipeline style (2.3) and allocation pressure
(the memory-audit theme). *Haxe/GHC:* short-cut fusion / `@:pure`-gated.

**3.2 — Whole-program indicator CSE (series-level)** ◆ · M
Ensure `sma(close,5)` referenced in three guards is computed *once* across the whole strategy, not
per-callsite. `SeriesLiveness`/`SeriesLowering` + `CommonSubexprElim` likely cover much of this at
scalar level; extend/verify at the **series/indicator** level. Pure honesty-neutral speedup.

**3.3 — Oracle memoization: compile once, run many** ▲ · M — *attacks the speed-plan whale*
`PLAN_EVO_SPEED.md` names the attribution oracle (`evalFn`) as the cost: it re-runs parse + the
full 8-pass compile + a tree-walk backtest **per ablation, serial, zero caching**. *Improvement:*
memoize the *compiled artifact* by structural hash (EvoCache exists for fitness — extend to the
compiled program/bytecode) so a mutated child recompiles only the changed subtree, not the world.
This is arguably the single biggest evo-speed win available and it's pure engineering, no algorithm risk.

**3.4 — Purity-driven hoisting** ◆ · S
With `@:pure` (2.4), hoist loop-invariant indicator computations out of the per-bar loop and
memoize across bars. Cheap once purity is known.

---

## Axis 4 — Runtime speed

**4.1 — A bytecode VM for the interp tier** ▲ · L — *top speed pick; the "stack language" idea*
*Current:* `MuseInterp` is a **tree-walker** — it re-dispatches on every AST node, every bar. It's
the steppable/debuggable tier *and* the slow serial path the attribution oracle leans on.
*Improvement:* compile the AST **once** to a flat instruction array and run a tight dispatch loop —
a **register or stack bytecode VM**. Tree-walk → bytecode is typically a **3–10× interpreter
speedup**, and it *stays steppable* (you step bytecode, keep the debugger). This is the classic
Lua/Python/CPython-vs-tree-walk lesson, and Haxe's own `eval` target is bytecode-ish. Pairs with
3.3 (compile-once): the compiled artifact you cache *is* the bytecode. **The highest-leverage
runtime change**, and it directly speeds the honest attribution oracle — more honest evaluations
per second is more honesty per dollar of compute.

**4.2 — Columnar / vectorized whole-tape evaluation** ▲ · M–L
*Current:* NMA already does columnar attribution; the general path is bar-at-a-time. *Improvement:*
generalize SoA/column-at-a-time evaluation across the whole strategy — evaluate an indicator over
all bars in one cache-friendly, SIMD-amenable pass, vs per-bar dispatch. The NMA columnar work is
the proof of concept; lift it to the general evaluator for the batch/backtest path (keep bar-at-a-
time only for the genuinely stateful/streaming case).

**4.3 — Boxing / allocation elimination via typed values** ◆ · M
The memory-audit theme is boxing/allocation on the hot path. The abstract-type system (2.1) gives
the JS/WASM emitters static `Float`/`Int` knowledge to emit unboxed locals and avoid `Dynamic`,
compounding with 3.1's fusion. Type information → unboxed codegen.

**4.4 — Default the hot path to the fastest tier** ◆ · S
`PLAN_EVO_SPEED` already has in-process `WatAssembler` + `--threads`. Make the WASM/compiled tier
the *default* for the attribution oracle (behind the parity gate), so the slow tree-walk interp is
reserved for stepping/debugging, not bulk evolution.

---

## The cross-axis shortlist (impact ÷ effort, honesty-aligned)

1. **Oracle compile-once memoization (3.3)** — biggest evo-speed win, pure engineering, no risk.
   *Do first.*
2. **Bytecode VM for the interp tier (4.1)** — 3–10× the hot serial path, stays steppable; the
   compiled artifact doubles as 3.3's cache key. *The big one.*
3. **Zero-cost abstract/unit types (2.1)** — catches the most expensive silent bug class at compile
   time, at no runtime cost; also the substrate for typed holes. *Correctness + speed + honesty.*
4. **Author-writable holes filled by the honest engine (1.2 + 1.3 SHole/typed holes)** — the
   standout *product* feature: the language becomes the customization surface, the engine fills,
   the instrument judges. *Unique to us.*
5. **Full macro hygiene (1.1)** — the compiler must never silently change what your code means.
6. **Stream fusion (3.1)** — allocation-free fluent pipelines; pairs with `|>` (2.3) + `using` (2.2).

## The through-line
The language wins that matter most are the ones that also serve the brand: **type safety that
catches silent bugs (2.1), a compiler that never lies about your code's meaning (1.1), an engine
that fills your sketches and tells you honestly if they're real (1.2), and a faster honest oracle
so we can afford *more* honesty per bar (3.3 + 4.1).** Expressiveness, speed, and integrity keep
turning out to be the same investment.
