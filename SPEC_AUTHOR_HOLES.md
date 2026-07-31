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
