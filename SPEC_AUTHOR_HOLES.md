# SPEC — Author-writable holes, filled by the honest engine

**Status:** Design spec, 2026-07-31. Unifies the two disconnected "hole" systems: compile-time
author metaprogramming (`macro`/`module`/`template`) and evolutionary synthesis holes
(`BHole`/`KHole`). Lets a human (or an agent) write a **strategy sketch** with unknowns, and the
evolutionary engine fills them **under the honest gate** — telling you honestly whether what it
found is real.

**One line:** *"Write the shape of the idea; let the engine find the rest; the instrument tells you
if it's a coin-flip anyway."*

This is the language feature that most directly serves the constitution: the language becomes the
**customization surface**, the engine the **fill mechanism**, the honest instrument the **judge**.

---

## 1. Surface syntax

A hole is introduced with `?`. It is legal anywhere a bool, scalar, or series expression is legal
inside a strategy body.

```
strategy MyIdea {
  onBar {
    when rsi(close, ?Scalar in 2..30) < ?Scalar in [10,40] and ?Bool: {
      long(?Scalar in [0.1, 1.0])
    }
    when ?Series ~ {sma, ema} crossesUnder close: { flat() }
  }
}
```

- `?` — **untyped** hole; type inferred from position (bool guard → bool hole; numeric arg →
  scalar hole; series position → series hole).
- `?Bool` / `?Scalar` / `?Series` — **typed** hole.
- `?Scalar in 2..30` (int range) · `?Scalar in [0.1,1.0]` (real interval) — **domain-constrained**.
- `?Series ~ {sma, ema, rsi}` · `?Bool ~ cross` — **family-constrained** (restrict the grammar the
  fill draws from; `~ cross` = the crossover/comparison family).
- **Named/shared holes:** `?len:Scalar in 2..200` declares a named unknown; later `len` references
  the *same* filled value everywhere (one decision, substituted consistently).

Grammar note: `?` is unambiguous — it can't begin any existing expression. It attaches an optional
type, an optional `in <domain>`, an optional `~ <family>`, and an optional `name:` prefix.

## 2. AST

New expression node (`ast/Expr.hx`):

```haxe
EHole(name:Null<String>, ty:Null<HoleType>, domain:Null<HoleDomain>);
```
```haxe
enum HoleType { HBool; HScalar; HSeries; }
enum HoleDomain {
  DIntRange(lo:Int, hi:Int);
  DRealInterval(lo:Float, hi:Float);
  DFamily(names:Array<String>);   // e.g. ["sma","ema"] or ["cross"]
}
```

Parser (`parse/StrategyParser.hx` + `MuseParser`): recognize a leading `?`, parse the optional
`name:`, type ident, `in` domain, `~` family → `EHole(...)`. Untyped `?` → `EHole(null,null,null)`.

## 3. Lowering: source → genome (the bridge)

The hole recognition slots into the existing source→genome path
(`CorpusSeed.translate{Bool,Scalar,Series}`), which already carry `allowed:Map<String,Bool>` for
the indicator whitelist:

- `translateBool` sees `EHole` (or infers bool by position) → emits `BHole(seed, domain)`.
- `translateScalar` → `KHole(seed, domain)`.
- `translateSeries` → **`SHole(seed, domain)`** (new — §4).

`seed` is a trivially-valid inner so an *unfilled* sketch still parses, type-checks, and runs as a
placeholder (bool-hole seed = always-true; scalar-hole seed = a midpoint of its domain, else 0;
series-hole seed = `close`). This preserves the "a sketch is a real program" invariant and lets the
edit-source round-trip (`HumanLoopWindow`) and `Expand.expand` handle holed genomes uniformly.

**Carrying the domain:** extend the hole constructors to hold their domain +
optional name:

```haxe
// evo/BoolNode.hx
BHole(inner:BoolNode, domain:Null<HoleDomain>, name:Null<String>);
// evo/ScalarNode.hx
KHole(inner:ScalarNode, domain:Null<HoleDomain>, name:Null<String>);
// evo/SeriesNode.hx  (NEW)
SHole(inner:SeriesNode, domain:Null<HoleDomain>, name:Null<String>);
```

Update the ~5 switch sites that already special-case holes (`Variation.boolHasHole/scalarHasHole`,
`Canonical.keyBool/countBool`, `TreeSurgery.collectBool`, `LearnedLibrary`). Backward-compat: a
plain internal hole passes `null, null`.

## 4. The series hole (`SHole`)

Today evolution can hole only bools and scalars — never *which indicator/series*. `SHole` closes
this: a series hole fills with a series subexpression (an indicator call, a price field, an arith
of series) drawn from `allowed` and constrained by `DFamily`. This is the single most requested
synthesis axis ("let the engine pick the indicator") and it's the substrate for `?Series` holes.

## 5. The fill loop (Variation, domain-aware)

`Variation` already fills `BHole`/`KHole` by mutating `inner` and `isTemplated` already gates the
byte-identical recording boundary (`armed = !isTemplated(g)`). Extend:

- **Domain-respecting fills.** A `KHole` with `DIntRange(2,30)` draws fills only in `[2,30]`; a
  `DFamily(["sma","ema"])` `SHole` only draws those indicators. `Variation`'s mutation becomes
  domain-parameterized instead of drawing from the full grammar → guided, not blind search.
- **Named/shared holes.** All occurrences of a named hole (`len`) share one fill: fill once per
  candidate, substitute everywhere; mutation perturbs the shared value.
- **Fill budget.** A sketch declares (or the CLI passes) a search budget; the engine samples/evolves
  fills within it.

Unfilled → still a valid program (the seeds). Fully-holed (`?` everywhere) → degrades gracefully to
the existing from-scratch synthesis. A sketch is just a *partially-frozen* genome.

## 6. The honest gate + anti-gaming (non-negotiable)

Filling K holes over a search of N candidates is a **multiple-testing machine** — exactly what the
leaderboard's field-N deflation exists for. **The effective search size feeds the DSR trials term**
(`ProbSharpe.dsr` / `LeaderboardScore.effectiveTrials`): the more the engine is allowed to fill,
the higher the bar the result must clear to be called real. A one-hole sketch is nearly free; a
ten-hole sketch with a big budget must beat a much taller null. This is the same anti-gaming math
already audited, applied to sketch-filling — and it is the honest heart of the feature:

> **"We filled your sketch. Even after searching N candidates, it's still a coin-flip — here's the
> deflated bar it failed to clear."**

Every fill result is a `runShare` receipt (source = the *filled* program, seed, tape, verdict,
digest) → reproduces bit-for-bit on `/verify`, and can go to the wall (its `nTrials` already
carries the search deflation).

## 7. UX

- **CLI:** `muse fill <sketch.ms> --tape <data> --budget <N> --seed <s>` → the best filled program
  + its honest verdict (DSR/PBO/wall-eligibility, deflated by N). Deterministic (seeded).
- **Studio:** write `?` in a strategy, hit **Fill holes** → the engine evolves fills live, then the
  Truth panel renders the verdict of the *filled* program — including, on-brand, the honest
  "still a coin-flip after filling, here's why." Shareable via the existing share-verdict loop.
- **Agent/API (B9):** the same `fill` as a programmatic endpoint — an agent submits a sketch, gets
  a filled program + a deflated honest verdict. The anti-gaming deflation is what makes this safe
  at machine scale.

## 8. Determinism / parity

Filled programs are **untemplated** genomes → byte-identical across interp/JS/WASM by the existing
gate (the `armed = !isTemplated` boundary already guarantees a *filled* genome records identically
to one written by hand). The fill *search* is seeded and reproducible. No new parity surface for
the filled artifact; the only new determinism obligation is that the *search* is seed-stable.

## 9. Edge cases
- **Type-infer failure** (untyped `?` in an ambiguous position) → a clear compile error naming the
  hole and asking for `?Type`, never a silent guess.
- **Hole in `size`/projection vs guard** → all valid; the 5-slot `isTemplated` scan already covers
  size; projections need the same scan added.
- **Nested holes** (`rsi(close, ?) < ?`) → independent holes unless named.
- **Empty domain / unsatisfiable family** → compile error at lower time.
- **All-holes sketch** → equivalent to unconstrained synthesis; the deflation makes its bar the
  tallest, honestly.

## 10. Round-trip
`sketch source (EHole)` ⇄ `genome (BHole/KHole/SHole + domain)` ⇄ `filled program (Expand.expand)`.
The Studio edit-source round-trip and `CorpusSeed`↔`Expand` inverse must preserve holes and their
domains (add `EHole` handling to `Expand.expand`'s printer and to `CorpusSeed`'s reverse path).

## 11. Phasing
- **P0** — `?` + `?Bool`/`?Scalar` → `BHole`/`KHole`; parser + `translate{Bool,Scalar}` recognition;
  domain-carrying hole constructors; `Variation` domain-aware fill; `muse fill` CLI; honest verdict
  **with search-N deflation**. Parity: filled artifact byte-identical (inherits existing gate).
- **P1** — `?Series` (`SHole`) + `DFamily`/`in` domains + named/shared holes.
- **P2** — Studio "Fill holes" UI + share-verdict receipt + the "coin-flip after filling" chrome.
- **P3** — holes inside `template`/`module` (a template with holes = a parameterized **sketch
  family**); higher-order fill.

## 12. Acceptance / definition of done
- A `?`-bearing strategy parses, type-checks, and runs as a placeholder unfilled.
- `muse fill` returns a filled program whose verdict is computed by the honest instrument and
  **deflated by the search size** (verify: more holes / bigger budget ⇒ strictly higher bar).
- A pure-noise sketch is reported **coin-flip after filling** (the negative control — if a noise
  sketch ever fills to "Robust," the deflation is broken: P0 bug, same as the leaderboard DoD).
- The filled program reproduces bit-for-bit on `/verify`.
- Determinism: same sketch + seed + budget ⇒ same fill.

## 13. Open questions
- Register vs side-table for domain metadata (spec picks enum-extension; revisit if the ~5 sites
  balloon).
- Whether named holes across *different* types are allowed (spec: no — a name binds one type).
- Interaction with `LearnedLibrary` motif reach-in (holes could draw fills from learned motifs — a
  natural P1+ enhancement: fill from *proven* subtrees, still deflated).

---

## 14. Deep-dive — the `muse fill` search loop (how fill + deflation actually wire)

Filling a sketch is a **constrained evolutionary search over the hole-vector only** — the frozen
skeleton never mutates. It reuses `EvolutionEngine`/`Variation`/`Fitness`/`EvoCache` wholesale;
the only new machinery is site collection, domain-aware sampling, and the effective-N wire.

**Step 1 — collect the sites.** Extend the existing detectors (`Variation.boolHasHole`/
`scalarHasHole`, which already recurse the 5 slots) into a *collector*:
```
collectHoleSites(g) -> Array<{ path:GPath, ty:HoleType, domain:HoleDomain, name:Null<String> }>
```
`path` reuses `TreeSurgery.GPath` (the same addressing `swapScore`/`replaceBool` use), so a fill is
just a `TreeSurgery.replace{Bool,Scalar,Series}(skeleton, path, inner)`. Named sites are grouped:
one logical unknown, N physical paths, filled with one shared draw.

**Step 2 — the domain-aware sampler** (this is all that's genuinely new in `Variation`):
```
sampleFill(ty, domain, rng) -> BoolNode | ScalarNode | SeriesNode
  DIntRange(lo,hi)     -> KConst( rng.int(lo, hi) )                  // scalar
  DRealInterval(lo,hi) -> KConst( lo + rng.float()*(hi-lo) )
  DFamily(["sma",...]) -> SInd( rng.pick(names), close, sampledLen ) // series
  DFamily(["cross"])   -> BCross(rng.pick(over|under), lhsHole, rhsHole)
  null (untyped)       -> draw from the full grammar for ty (today's Variation behavior)
```
Mutation of a filled site perturbs *within* its domain (a `DIntRange` len does ±k clamped to
`[lo,hi]`; never leaves the box). This is the one behavioral change to `Variation`: when the site
being mutated is a hole with a domain, route through the domain sampler instead of the free grammar.

**Step 3 — the search.** Seed a population by sampling every site; evolve with **hole-only**
variation (the skeleton is immutable — the existing `armed = !isTemplated` boundary already makes
`Variation` treat non-hole subtrees as frozen, so this mostly falls out). Score with `Fitness`
against the tape; `EvoCache` dedupes identical fill-vectors by structural key. Budget = `pop×gens`
(or a flat sample count) = **N_eval**, the count of *distinct fill candidates actually evaluated*
(cache hits don't re-count — a hit is the same trial, not a new one).

**Step 4 — the effective-N deflation (the honest heart).** The winner's verdict is computed at
`nTrials = N_eval` (distinct candidates), fed exactly where the leaderboard feeds field size:
```
best   = argmax_fill Fitness.score(evaluate(fill), minTrades)
dsr    = ProbSharpe.dsr(best.returns, N_eval)          // deflated by the search
verdict = OosVerdict(best, dsr, pbo, ciLo, ...)         // same gate as everywhere
```
So a 1-hole sketch searched 30 ways clears an easy bar; a 10-hole sketch searched 5,000 ways must
beat `expectedMax`-of-5000 under the null (`sr0 = expectedMaxSr(5000, …)`). The monotone
`ProbSharpe.dsr` deflation I audited (N↑ ⇒ bar↑) *is* the anti-gaming here — no new math, just the
search size wired into the existing trials term. Report the **deflated** verdict, never the raw best.

**Step 5 — emit.** Replace each hole with its winning inner (`TreeSurgery.replace…` down the frozen
skeleton) → an untemplated genome → `Expand.expand` → filled source. Bundle
`{ filledSource, seed, tapeId, N_eval, verdict, equityDigest }` as a `runShare` receipt.

**Determinism.** One `DetRng` seeds sampler + evolution; `EvoCache` is structural; so
`(sketch, seed, budget)` ⇒ the identical fill and the identical deflated verdict, reproducible on
`/verify`.

**The negative control (DoD §12).** Run a pure-noise sketch (all `?`) on a driftless tape: the best
fill of N *must* come back **Coin-flip** because `dsr(noise, N)` collapses as N grows. If a noise
sketch ever fills to Robust, `N_eval` isn't reaching the trials term — a P0 leak, identical in kind
to the leaderboard's "noise flood tops the board" P0.

**CLI shape:**
```
muse fill sketch.ms --tape data.csv --budget 2000 --seed 1337
# -> filled.ms  +  { verdict: "Coin-flip", dsr@2000: 0.03, pbo: 0.41, nEval: 2000, ciLo: -0.4 }
```

---

## 15. STATUS — P0 landed (branch `feat/author-holes`), P1 handoff for Cursor

**P0 shipped and verified end-to-end** (parse → lower → fill → honest verdict), 5 commits:
- `33b1a4f` P0.1 parser: `?`/`?Bool`/`?Scalar`/`?Series` → `EMeta("__hole",[ty],seed)` in
  `StrategyParser.parsePrimary`. No new `Expr` variant (EMeta ⇒ zero exhaustiveness blast radius;
  unfilled sketch runs via the interp's `EMeta` fallthrough).
- `c8a9ea8` P0.2 lowering: `CorpusSeed.translate{Bool,Scalar}` map `__hole` → `BHole`/`KHole`
  (surface sibling of the existing `evolve(...)` marker). Sketch → templated genome.
- `e574e28` P0.3/P0.4: `Variation.fillHoles` (public) + `cli/MuseFill` search loop; effective-N
  deflation via `ProbSharpe.dsr(returns, nEval)`. Negative control passes (noise → Coin-flip).
- `983edf8` P0.5: positive control (momentum tape → Robust). Gate tells the truth both ways.

**P1 — for Cursor (deliberate, wide-blast-radius; verify each with the `MuseFill` demo pattern):**

1. **Domain-carrying holes + `?Scalar in 2..30` / `?Series ~ {sma,ema}` / named `?len:`.**
   - Parser (`StrategyParser.parsePrimary`, the `?` branch): after the type, parse optional
     `in <int>..<int>` / `in [<f>,<f>]` and `~ { name, ... }` and a leading `name:`; encode into
     the `EMeta("__hole", …)` args (positional `EConst`/`EArrayDecl`).
   - **Extend the hole constructors to carry the domain+name** — `BHole(inner, ?domain, ?name)`,
     `KHole(inner, ?domain, ?name)`. **Switch sites to update** (found during P0):
     `evo/BoolNode.hx` + `evo/ScalarNode.hx` (defs), `Variation.boolHasHole/scalarHasHole` +
     the new `refillBool/refillScalar`, `CorpusSeed.translate{Bool,Scalar}`,
     `Canonical.key*/count*`, `TreeSurgery.collect*`, and any `Expand` hole handling. Grep
     `BHole(`/`KHole(` first — it's a small, enumerable set.
   - `Variation.fillHoles`: make `growScalar`/`growBool` **domain-aware** (clamp `KConst` to the
     range; restrict indicator family) — see §5 `sampleFill`.

2. **`SHole` (series hole).** New `SeriesNode` variant `SHole(inner, ?domain, ?name)`. Update
   `translateSeries` (emit it), `Variation` series growth + a `seriesHasHole`/`refillSeries`,
   `Canonical` series keying, `Expand.series`. This is the novel "let the engine pick the
   indicator" axis — highest expressiveness payoff.

3. **Constrained evolution** (replace P0 random-search): drive `EvolutionEngine` with hole-only
   variation (the `armed = !isTemplated` boundary already freezes the skeleton). Keep
   `fillHoles` as the seed/sampler seam.

4. **OOS hardening.** `MuseFill.run` currently scores full-sample; wire `Fitness.evaluate(…,
   honestOos=true)` + purge/embargo so the verdict is OOS-honest, not just deflation-honest.

5. **Size-slot holes.** `translateStrategy` hardcodes `size: KConst(1.0)` and discards order-call
   args — teach it to translate `long(<scalar>)` → `g.size` so `?Scalar` there is fillable.

6. **Studio "Fill holes" button** (mederos-web + muse-runtime): expose `fill` over the runtime
   API; the Truth panel renders the *filled* verdict, incl. the honest "coin-flip after filling"
   chrome + a `runShare` receipt. (Conversion/virality tie-in.)

7. **Determinism/CLI polish.** File-arg + flags (`--budget/--seed/--tape`), and emit the fill as a
   reproducible `runShare` receipt.
