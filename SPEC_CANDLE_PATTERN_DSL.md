# SPEC — Sequential Candle-Pattern DSL (human-authored **and** evolution-discovered)

Status: **design proposal**. Nothing here is built yet. The goal is a MuseScript sub-language for
describing **sequences of candles** that is (a) genuinely pleasant to hand-write and (b) a
first-class, mutable citizen of the evolution engine's genome — so the *same* construct a human
sketches, the evo loop can discover, tune, and cross-breed.

## 0. Why this, and why co-design both audiences at once

Today a candlestick pattern in MuseScript is spelled out longhand — `close[1] < open[1] && close[0]
> open[0] && close[0] > open[1] && open[0] < close[1]` for a bullish engulfing — which is verbose,
brittle (hard equalities), scale-dependent (raw price deltas mean nothing across BTC vs EURUSD), and
**opaque to the evolution engine** (it's an arbitrary boolean tree, so the GP palette can't reason
about "this is a 2-bar reversal shape" and mutate it as such).

The two audiences pull in the *same* direction if we get the representation right:

| Human wants | Evolution wants | Shared solution |
|---|---|---|
| Read like the pattern's name | A structured, typed node it can mutate | One AST node: an ordered list of per-bar *slots* |
| Not hand-tune 8 thresholds | Few, bounded, tunable knobs | Features **normalized to range/ATR units** (scale-free) + fuzzy tolerances that ARE the knobs |
| Robustness (don't over-fit one bar) | Generalization across instruments/regimes | Soft matching (a match *score* in [0,1]), not hard equality |
| Compose with the rest of a strategy | A `Bool`/`Scalar` leaf like any other | The pattern evaluates to a `Scalar` match-score, usable anywhere |

The design rule for everything below: **every surface construct must have an obvious genome node,
and every genome node must render back to readable surface syntax** (the same dual-representation
discipline `Expand`/`CorpusSeed` already enforce for the rest of the language).

## 1. Layer 1 — the candle vocabulary (scale-free, per-bar)

A single candle at relative index `i` (`0` = current, `1` = prior, …) exposes normalized features.
**Normalization is the crux**: every magnitude is expressed as a fraction of that bar's own range
(or a rolling ATR), so a pattern learned on one instrument transfers to another — the property the
evo engine's walk-forward gate rewards.

```
candle(i).body        # signed (close-open) / range        in [-1, 1]
candle(i).body_abs    # |close-open| / range               in [0, 1]
candle(i).upper_wick  # (high-max(open,close)) / range      in [0, 1]
candle(i).lower_wick  # (min(open,close)-low) / range       in [0, 1]
candle(i).dir         # sign(close-open)                    in {-1,0,1}
candle(i).range_atr   # range / atr(close, N)               scale-free size
candle(i).gap         # (open(i) - close(i+1)) / atr        gap vs prior close
```

- **Hand-writing:** `candle(0).body > 0.6` = "current candle is a strong bull body". `candle(0).lower_wick > 0.5 && candle(0).body_abs < 0.3` = "hammer-ish".
- **Genome:** each `candle(i).<feat>` is a new `ScalarNode` leaf `SCandle(i:Int, feat:String)` — sibling to `SPrice`/`SInd`. It slots into the existing catalog (`EKind.EScalar`); mutation tweaks `i` (bounded 0..K) and `feat` (a small closed set). Zero new machinery in the fitness backends beyond the leaf's per-bar compute (all derivable from OHLC via `close[i]`-style lookback, which already exists).

## 2. Layer 2 — the pattern block (the sequence)

The headline construct. A `pattern` names an ordered sequence of **bar-slots**, each slot a soft
predicate over that bar's candle features. It evaluates to a **match score in [0,1]** (1 = every
slot fully satisfied), not a hard bool — so it's robust AND differentiable-ish for the search.

```muse
pattern bullishEngulf {
  bar -1: dir < 0 && body_abs > 0.3      # prior: a real down candle
  bar  0: dir > 0 && body_abs > 0.5      # now:  a strong up candle
  bar  0: engulfs(-1)                    # cross-bar relation: body engulfs prior body
}

strategy S {
  onBar {
    when bullishEngulf >= 0.8 && close > sma(close, 50): long()
  }
}
```

- **Slots are relative** (`bar -1`, `bar 0`); `bar -k` is `candle(k)`. Cross-bar relations
  (`engulfs`, `higher_high`, `inside`, `gap_up`) are a small closed builtin set over two slots.
- **Score, not bool:** each slot's soft predicate yields a per-slot satisfaction in [0,1] (a
  smoothstep over the threshold with a tolerance band); the pattern score is their product (AND) or
  a weighted mean. `pattern >= τ` is then an ordinary `BoolNode.BCmp`. Humans read `>= 0.8` as "a
  clean match"; the evo engine tunes `τ` and the per-slot tolerances as bounded `HoleDomain` knobs.

### Genome representation (the whole point)

A pattern is one new node, structured for mutation:

```
SPattern {
  slots: Array<{ rel:Int, pred: BoolNode-over-SCandle-leaves, weight:Float }>,
  reduce: "product" | "wmean",
}
```

Mutation operators the evo engine gets, each a natural, bounded edit:
- **grow/shrink** the sequence (add/remove a slot — bounded 1..K bars);
- **retune** a slot's tolerance / threshold (`HoleDomain` real-interval, like other numeric holes);
- **swap** a slot's feature or a cross-bar relation (closed vocabulary → safe mutation);
- **re-weight** slots (`wmean` reduce).

Because slots are a *list of typed sub-predicates*, crossover between two evolved patterns is
meaningful (splice slot-subsequences) — unlike splicing arbitrary boolean trees. This is the same
win `BFeature`/the closed palette gave seeding: structure the evo engine can exploit.

`Expand` renders `SPattern` back to the `pattern { … }` surface (dual-representation contract);
`CorpusSeed` reverse-translates a hand-written `pattern` block into an `SPattern` so human-authored
patterns **seed** the population — closing the human→evolution loop the project is built around.

## 3. Layer 3 — temporal operators (folds in `bars_since`)

Sequential patterns need "how long ago" and "has X happened recently" — the same per-callsite state
`rising`/`falling`/`crossover` already keep (`TradeBuiltins.trendCS` + `CallsiteIds.isStatefulKind`).
Add three, all on that existing machinery (a `*CS(harness, id, …)` compiled variant + a slot-based
interp variant, and one line in `CallsiteIds.isStatefulKind`):

```
bars_since(cond)        # bars since cond was last true (sentinel if never)   -> Scalar
count_recent(cond, n)   # how many of the last n bars had cond true           -> Scalar
held(cond, n)           # cond has been true for the last n consecutive bars  -> Bool
```

`bars_since` alone unlocks the wishlist's "setup memory" (`bars_since(bullishEngulf >= 0.8) <= 5`) —
and it's the shared temporal substrate the pattern block leans on. **These are the reason `bars_since`
was deferred into this spec**: it's the same callsite-state feature, best built once, here.

Genome note: `bars_since`/`count_recent`/`held` are stateful `BoolNode`/`ScalarNode` leaves — the evo
engine treats them like `rising`/`falling` (already in the palette), so they're discoverable for free.

## 4. Runtime / backends (cost-aware)

- **Interp**: direct per-bar compute from the OHLC ring buffer — trivial.
- **JS backend**: `SCandle` leaves and slot predicates compile to the same inline arithmetic
  `SPrice`/lookback already emit; the pattern reduce is a small fold. No new dispatch surface beyond
  the leaves.
- **WASM / VM**: `SCandle` is pure OHLC arithmetic → emittable. A whole `pattern` with many slots
  may exceed the VM's subset → it falls back to interp/compiled, exactly like today's out-of-subset
  tail (`nma-unsupported`/`vm-unsupported` → `evaluateCompiled`). No correctness risk.
- **Columnar NMA**: `SCandle` features are per-bar columns → fully columnarizable (fast for evo).
  Only the cross-bar *relations* need a 2-column op; add them to the NMA op set or let those genomes
  fall back (measured, not guessed).

## 5. Phased plan

- **P0 — the candle vocabulary.** `SCandle(i, feat)` scalar leaf + the ~7 normalized features, in
  interp + JS + `BuiltinSigs` + a palette entry. Verify: hand-written `candle(0).body > 0.6` matches a
  reference computed from OHLC; js/interp parity; one evo smoke run shows the leaf getting mutated.
  *Ships value immediately* (scale-free candle features) with zero new grammar.
- **P1 — `bars_since` / `count_recent` / `held`.** The temporal trio on the existing callsite-state
  path. Verify: `bars_since` parity vs a brute-force scan; stateful-kind registration; palette entry.
- **P2 — the `pattern { … }` block + `SPattern` genome node.** Parser (a new decl, like `template`),
  `Expand` render, `CorpusSeed` reverse-translate, soft-score reduce, the four mutation operators,
  MAP-Elites descriptor (e.g. sequence length × mean tolerance) so patterns niche apart. Verify:
  hand-written engulfing scores 1.0 on a synthetic engulfing bar; an evo run *discovers* a
  positive-edge pattern on held data and it survives the walk-forward + PBO/DSR gate (the real bar —
  a discovered pattern that doesn't generalize is a NO-GO, logged like every other).
- **P3 — cross-bar relation vocabulary + fuzzy calibration.** `engulfs`/`inside`/`gap_up`/… as a
  closed set; tune the smoothstep tolerance defaults against a labelled pattern set.

## 6. Open questions (flagged, not hand-waved)

- **Soft-score reduce shape.** Product (strict AND) vs weighted-mean (graceful) changes both
  hand-feel and the search landscape. Start with product for interpretability; A/B the search
  behavior in P2 — don't guess.
- **Normalization denominator.** Per-bar range is simplest but a doji (range≈0) explodes the ratio;
  clamp with a small ATR floor. Rolling ATR is steadier but adds a window param to tune.
- **Lookahead discipline.** `bar -k` reads only *past/current* bars — trivially causal — but the
  soft tolerances must be fixed at author/seed time, never fit using the eval window (same PIT
  discipline as every other feature; enforce in the fitness harness, not the DSL).
- **Palette blow-up.** `SCandle` (K indices × ~7 feats) + relations widens the mutation search;
  cap `K` (e.g. ≤ 5 bars) and gate the relation set so gen-0 diversity stays useful, not noise.
- **Where patterns are NOT genome space.** Deeply nested/hand-crafted patterns (many slots) belong
  to hand-authoring; the evo engine should be capped to short sequences. Same split the Jormungandr
  plan draws for `Frame.forkChild` (hand-author-only) vs the genome-level counterfactual node.

## 7. Relationship to the rest of the roadmap

This shares its temporal-state substrate with `bars_since` (wishlist P1) and its
"structured-for-evolution" philosophy with the fail-open `BFeature` seeding and the closed GP
palette. It's also the natural carrier for **event-driven patterns** once the Jormungandr event bus
lands (`SPEC`/`JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`): a slot predicate could reference a
`world.*` event feature, making "candle shape *plus* a shipping-data shock" a single discoverable
pattern. Design the slot predicate vocabulary to be open to non-OHLC features from day one.
