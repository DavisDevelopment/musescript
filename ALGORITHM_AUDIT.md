# Algorithm & robustness audit — muse-script

*2026-07-26. Scope: 904 `.hx` files / ~140k lines. I targeted the algorithmically dense
areas (numerics, RNG, selection/sorting, evolution, indicator hot loops, macro
infrastructure) rather than reading every line — a genuinely exhaustive line-by-line pass
over 140k lines isn't something I did, and I don't want to imply otherwise. Every finding
below was verified by reading the code and, where possible, by running it.*

Two things worth saying up front, because they shape everything else:

- **The numerics library is already better than the code that consumes it.**
  `StatsBuiltins` has Kahan/Neumaier compensated summation, Welford variance, and an online
  co-moment covariance. Several fitness-critical paths hand-roll naive versions instead of
  calling it. Most of the "modernize the algorithm" wins here are *"use the good thing you
  already built"*, not *"go implement something new."*
- **The evolution engine is genuinely sophisticated** — ε-lexicase, tournament, archipelago
  demes, MAP-Elites/CVT, novelty, speciation, windowed robust scoring with a CVaR-of-window-
  Sharpes objective. I checked before recommending, and deliberately dropped several
  suggestions (NSGA-II, lexicase, novelty search) because they're already implemented.

---

## Status

| # | Finding | Status |
|---|---|---|
| §1 | `Rand.bool()` alternation **+ `int(n)` even-modulus defect** | ✅ **FIXED** 2026-07-26, 6 regression tests added |
| M1 | Duplicate indicator-name detection | ✅ **FIXED** 2026-07-26 (build-time macro + runtime guard, failure verified) |
| §2 | RingBuffer migration | 🟡 **40 of 201 done** 2026-08-02, golden-verified bit-identical; found + fixed a reversed-index trap |
| §3 | 15 window-re-sorting indicators | open |
| §4 | Sharpe hardcoded `sqrt(252)` | ✅ **FIXED** 2026-08-02 — parameterized at all 5 sites + 3 tests |
| §5 | Fitness path bypassing `StatsBuiltins` numerics | ⛔ **WITHDRAWN** — see §5, the original recommendation was wrong |
| §6 | Two median definitions | ✅ **FIXED** 2026-08-02 |
| §7 | `MurmurationRng` word size + JS/JVM overflow | open |
| M2–M5 | Further macro guardrails | open |

**§1 turned out materially worse than first written**, and the original text below is left intact
with the correction inline — the initial pass under-scoped it by testing `int(10)`'s *histogram*
(perfect) instead of its *serial* behaviour (broken).

---

## 1. 🔴 ✅ FIXED — `Rand.bool()` returned a perfect alternation, and `int(n)` was broken for every even `n`

`musescript/evo/Rand.hx`

```haxe
public function int(n:Int):Int {
    state = (imul32(state, 1103515245) + 12345) & 0x7fffffff;
    return n == 0 ? 0 : state % n;
}
public function bool():Bool { return int(2) == 0; }
```

Classic LCG failure: for an odd multiplier and odd increment mod 2^k, **bit 0 is exactly
`(prev + 1) mod 2`** — it alternates deterministically. `bool()` reads that bit via `% 2`.

I replicated `Rand` exactly (including `imul32`) and ran it:

```
bool() first 24 draws, seed 7:   101010101010101010101010
seeds 1 / 42 / 1337 / 99999 / -5: all perfect alternations
consecutive-equal pairs in 100,000 draws: 0
true/false balance over 100k:    50000 / 50000   ← perfectly "uniform"
int(4) first 24 draws:           012301230123012301230123
```

**Why this survived to now:** every marginal/histogram check passes *perfectly* — 50/50
balance, uniform `int(4)` counts. Only a serial-correlation test reveals it. `int(10)` and
`float()` are fine (they consume more than the low bits; `float()` lag-1 autocorrelation
measured −0.0003, and threshold rates are accurate to 0.001).

**Live impact — one call site, and it matters.** `musescript/evo/SymbolSelector.hx:41`:

```haxe
/** Uniform per-gene crossover: each weight independently comes from `a` or `b` with equal
 * probability -- the simplest correct real-valued crossover ... */
child.weights = [for (i in 0...a.weights.length) rng.bool() ? a.weights[i] : b.weights[i]];
```

The docstring states the intent precisely, and the RNG silently violates it: instead of
sampling one of 2^n crossover masks, this produces the **fixed alternating mask**
`a[0], b[1], a[2], b[3], …` on every call (one of only two masks, depending on the parity of
the preceding draw). Symbol-weight crossover explores ~2 of 2^n recombinations.

### ⚠️ Correction — the defect was not confined to `bool()`

The first pass called `int(10)` "fine" on the strength of its histogram. That was wrong.
Measuring *serial* behaviour across moduli:

```
        immediate repeats over 60k draws     (fair die ≈ N/n)
int(2)        0      int(3)  20093 ✓      int(4)        0
int(5)    12215 ✓    int(6)      0        int(7)   8736 ✓
int(8)        0      int(10)     0        int(16)       0     int(32)  0
```

**Every even modulus had zero immediate repeats.** For even `n`,
`state % n ≡ state (mod 2)`, so the alternating bit 0 forces consecutive draws into opposite
parity — they can never be equal. Odd moduli were unaffected.

That reaches the engine's most important operator: `EvolutionEngine.tournamentSelect` samples
`selectionRng.int(ranked.length)` repeatedly and populations are even (default 8, runs use
`--pop 64`), so **no two consecutive tournament candidates could ever be the same
individual** — a systematic, seed-independent distortion of selection.

### What shipped

`int(n)` now scales the full state instead of taking a modulus, and `bool()` reads bit 30:

```haxe
inline function next():Int { state = (imul32(state, 1103515245) + 12345) & 0x7fffffff; return state; }
public function int(n:Int):Int { if (n == 0) return 0; return Std.int((next() / 2147483648.0) * n); }
public function bool():Bool { return next() >= 0x40000000; }
```

Verified after the change:

```
int(2..64): immediate repeats all within ±10% of the fair-die rate
bucket uniformity within sampling noise (0.18%–5.4% max deviation)
out-of-range draws in 3,000,000 × int(7): 0        (state < 2^31 ⇒ quotient < 1.0)
bool(): p=0.5009, consecEqual=59956/120k (fair ≈60000), longest run 15
int(64) consecutive collisions: 1875/120k vs fair 1875   — was exactly 0
```

Scaling also removes `%`'s modulo bias entirely. `next()` is the single state-transition site,
so every accessor still consumes exactly one step — `RngStreams`' "same seed, same experiment"
draw-count guarantee is preserved.

**Cost, stated plainly:** draw *sequences* changed, so runs archived before 2026-07-26 will not
replay bit-identically from the same `--seed`. Stored artifacts (elites, champions, cached
fitness) are unaffected; a re-run of an old seed is a new experiment, not a reproduction. There
is no way to fix the distribution without changing the sequence, so this was traded
deliberately and recorded in `Rand`'s class doc. The full suite (64,144 assertions) passes.

**6 regression tests added** (`TestEvoVariation`), all asserting *serial* properties — the
class of test that was missing, since every marginal check passed throughout:
`testRandBoolProducesConsecutiveRepeats`, `testRandBoolHasRunsLongerThanOne`,
`testRandBoolStaysRoughlyBalanced`, `testRandBoolIsStillDeterministicPerSeed`,
`testRandSmallIntDrawsAreNotACycle`, `testSymbolSelectorCrossoverExploresMoreThanOneMask`.

---

## 2. 🟡 PARTLY DONE — `RingBuffer` was built to kill `Array.shift()`, then adopted in 9 of ~210 indicators

### What shipped 2026-08-02 — and the trap that had to be fixed first

Adoption went **9 → 49**; `.shift()` call sites **201 → 154**. Every one of the 452 indicators
produces **bit-identical output** before and after, proven by a new snapshot tool rather than
asserted (see below).

**The first attempt was wrong, and silently so** — which is almost certainly why this migration
stalled at 9 files in the first place. `RingBuffer` indexes **newest-first**
(`at(0)` = most recent push) while the `Array` window it replaces indexes **oldest-first**
(`window[0]` = oldest). `@:arrayAccess` maps `buf[i]` onto `at(i)`, so a mechanical
`Array<Float>` → `RingBuffer<Float>` swap keeps compiling and reads the window **backwards in
time**. Worse, the two access paths within `RingBuffer` disagree with each other — verified by
probe, pushing 1..6 into a capacity-4 buffer:

```
at(i) / buf[i] :  [6, 5, 4, 3]   ← newest-first
for (v in buf) :  [3, 4, 5, 6]   ← oldest-first (matches Array)
```

That first pass changed **16 indicators' output**, ranging from sub-ULP summation-order noise
(`bipower_variation`) up to wholesale sign flips in running-peak drawdown ratios
(`burke_ratio` went `0, 0, 0, 3.33…` → `-0.185, -0.173, -0.168…`). All 16 were caught by the
golden diff, and the whole batch was reverted to a verified-identical baseline before retrying.

**Fixes applied so the migration is now safe by construction:**
- Added `RingBuffer.oldest(i)` — explicit oldest-first accessor, identical indexing to the
  `Array` window being replaced. Implemented purely in the abstract (`at(length-1-i)`), so
  neither the Float fast path nor the generic impl needed touching.
- Documented the reversal loudly on both `at()` and the class docstring, which previously
  claimed usage "matches the plain-`Array<T>` … pattern as closely as practical" without
  flagging the one place it emphatically does not.
- New `TestRingBuffer` (10 tests) pins **both** orders, their exact-reverse relationship,
  `push` eviction, the partially-filled warmup case, and that the generic impl matches the
  Float one — so nobody "fixes" one direction and breaks the other.

**New tool: `musescript/tools/IndicatorGolden.hx` + `golden.hxml`.** Dumps every registered
indicator's full per-bar output over a fixed synthetic tape, one line each, full float
precision. `diff` before/after is the acceptance test for any change claiming numerical
neutrality:

```bash
haxe golden.hxml && node build/js/indicator-golden.js > /tmp/before.txt
# ...change...
haxe golden.hxml && node build/js/indicator-golden.js > /tmp/after.txt
diff /tmp/before.txt /tmp/after.txt      # must be empty
```
452 indicators, 440 exercised (12 reject the synthetic args on constructor constraints —
stable, so still diffable).

### The remaining 154

The migration script deliberately refuses anything it can't prove mechanical, and the compiler
caught a category the script missed (windows *passed* to `Array<Float>`-typed helpers, e.g.
`FourierMath.spectrum(buf)` / `LinReg`). Remaining blockers, by class:

| blocker | count | note |
|---|---|---|
| field isn't `Array<Float>` (candlestick/profile structs) | ~14 | needs the generic impl + per-file review |
| passed to an `Array<Float>` helper | ~9 | either overload the helper or materialize |
| array-only API (`.copy()`, `.slice()`, `.sort()`) | ~7 | mostly the §3 re-sorting set — fix together with §3 |
| multi-array / return-value-consuming shifts | ~120 | not mechanical; individually cheap but needs eyes |

Recommend finishing in that order, re-running the golden diff each batch. **M3** (a build-time
lint banning `.shift()` in `indicators/lib/`) should land once the count reaches zero, or it
will regress one new indicator at a time.

### Original finding

`musescript/indicators/RingBuffer.hx` — its own docstring:

> *"Fixed-capacity circular buffer for rolling-window indicators, replacing the `Array<T>` +
> `.shift()` + `.push()` pattern used throughout `indicators/lib/*` … `Array.shift()` is
> O(n) — a real remove-and-compact, not a lazy head pointer — so every windowed indicator
> paid O(period) per bar just to evict the oldest sample; this pays O(1)"*

Measured adoption:

| | count |
|---|---|
| `indicators/lib/*.hx` using `RingBuffer` | **9** |
| `indicators/lib/*.hx` still calling `.shift()` | **201** |

This is a started-and-unfinished migration, and it's the single highest-leverage mechanical
change available: the target structure exists, is `@:multiType` (so it gets a real unboxed
`double[]` on the JVM — which the docstring documents was verified by decompilation), and
already has 9 reference adopters to copy the pattern from (`RollingMinMaxScaler`,
`HurstExponent`, `SsaCycles`, …).

Given `runPanel` does ~320k cells/s across a universe, O(period) → O(1) eviction on 201
indicators is a broad, low-risk throughput win with **zero numerical change** (same values,
same order, just a different eviction mechanism) — which also makes it easy to gate behind
an exact-equality regression test per indicator.

---

## 3. 🟠 15 indicators re-sort the entire window on every bar

Every one of these both `.shift()`s **and** full-sorts a window copy per update:

```
AdaptiveLaguerreFilter  BomarBands  CommonSenseRatio  ConditionalValueAtRisk
MedianAbsoluteDeviation MedianChannel  MedianMa  QuartileBands  RegimeLabel
RollingIqr  RollingQuantile  SpearmanCorrelation  TailRatio  ValueAtRisk  VolatilityCone
```

`RollingQuantile.update()` is representative — and its doc is honest about it
(*"Each update copies the window into a scratch buffer and sorts it"*):

```haxe
if (window.length == period) window.shift();   // O(period)
window.push(value);
var scratch = window.copy();                    // O(period)
scratch.sort(...);                              // O(period log period)
```

So O(k log k) per bar, O(n·k log k) per series. Modern options, in increasing effort:

1. **Sorted window + binary-search insert/delete over a ring buffer** — O(log k) search,
   O(k) memmove but with a tiny constant and no allocation. Usually a 5–20× win in practice
   and by far the least invasive; keeps exact type-7 interpolation semantics.
2. **Two-heap (max-heap lower half / min-heap upper half)** — the standard streaming-median
   structure, O(log k) per update. Exact for the median case (`MedianMa`, `MedianChannel`,
   `MedianAbsoluteDeviation`) but awkward for arbitrary quantiles.
3. **Order-statistic tree / indexable skiplist** — O(log k) for *any* quantile, exact;
   the right answer for `RollingQuantile`/`QuartileBands`/`RollingIqr`/`ValueAtRisk`/`TailRatio`.
4. **P²  or t-digest** — O(1) streaming quantile estimators. **I'd avoid these here**: they're
   approximate, and approximation inside a fitness-visible indicator is exactly the sort of
   silent inaccuracy this project's whole validation posture is built against. Only worth it
   if a specific indicator becomes a proven bottleneck and its consumers can tolerate error.

Recommendation: **(1) for all 15** as one mechanical pass (exact, cheap, testable), then **(3)**
for `RollingQuantile` specifically if it shows up hot in a `jit_audit_run.sh` profile.

Note `MedianAbsoluteDeviation` sorts **twice** per bar (window, then deviations) — best
single candidate for the two-heap treatment.

---

## 4. ✅ FIXED — Sharpe hardcoded `sqrt(252)` in every fitness path

### What shipped 2026-08-02 — and a correction to (b) below

**The annualization half was real and is fixed.** `Metrics.sharpe` / `Metrics.sortino`,
`OrderSim.sharpeOnline`, `NmaFitness.sharpeOfEquity`, `BlockBootstrap.annSharpe` and
`ProbSharpe.rankFromAnnualized` all now take `periodsPerYear`, defaulting to a shared
`Metrics.DAILY_PERIODS_PER_YEAR` — so existing daily results are byte-for-byte unchanged while
sub-daily tapes can finally be annualized correctly. Added
`Metrics.periodsPerYearFromBarSeconds(barSeconds, sessionSeconds, sessionsPerYear)` so callers
get a tested conversion instead of hand-rolling one (15m continuous → `96 × 365`; 15m on a 6.5h
equity session → `26 × 252`; degenerate input falls back to the daily default rather than
returning 0/∞).

`BlockBootstrap.annSharpe` and `ProbSharpe.rankFromAnnualized` are a **round-trip pair** (one
multiplies by √N, the other divides to recover per-period), so both were parameterized together
with a comment on each saying the factors must match — a mismatch there would silently rescale
the PSR/DSR rank.

### ⚠️ Correction — "(a) Triplication" was a misread

The audit called the three implementations a standing divergence risk to be deduplicated. Reading
them properly during implementation shows the duplication is **deliberate and load-bearing**:
`OrderSim.sharpeOnline` and `NmaFitness.sharpeOfEquity` are allocation-free variants that avoid
materializing the equity/returns arrays on hot paths, and both document themselves as bit-exact
with `Metrics.sharpe` (`"…so !trackCurve stays bit-exact with the equity → returns → sharpe
path"`). `Fitness.assertNmaParity` compares NMA vs compiled at **1e-9**. Merging them would
undo a real optimization; changing one in isolation would break a documented contract.

So the right fix wasn't deduplication — it was **enforcement**. Added
`testSharpeImplementationsAgreeBitExactly`, which drives a real `OrderSim` through its streamed
`markReturns` path and asserts it matches the materialized `equity → returns → sharpe` path to
1e-12 on the same 400-bar curve. Plus `testSharpeAnnualizationIsConfigurable` and
`testPeriodsPerYearFromBarSeconds`. The convention is now a test, not a comment.

*(`NmaFitness.sharpeOfEquity` is private, so the test covers the two reachable
implementations; the third stays covered at runtime by `assertNmaParity`. Stated here rather
than letting the test name imply more coverage than it has.)*

**Still open:** the parameter exists but nothing yet *passes* a non-default value — wiring real
bar resolution through the harness touches 20+ call sites and needs a decision on where
resolution lives (`BarFeed`? inferred from bar spacing?). The fix makes the correct behaviour
expressible; making it automatic is a separate change.

### Original finding

| Location | annualization |
|---|---|
| `harness/Metrics.hx:17` (`sharpe`) | `Math.sqrt(252)` |
| `harness/Metrics.hx:42` (`sortino`) | `Math.sqrt(252)` |
| `harness/OrderSim.hx:368` | `Math.sqrt(252)` |
| `evo/nma/NmaFitness.hx:515` | `Math.sqrt(252)` |

Two problems:

**(a) Triplication.** All four are currently algorithmically consistent (two-pass mean then
sum-of-squared-deviations, ddof=1, guard `std==0`) — I diffed them. But four copies of the
objective function the entire search optimizes against is a standing divergence risk: a fix
to one silently won't reach the others. This is *the* function where drift is most expensive.

**(b) Hardcoded daily annualization, in a codebase that runs sub-daily.** The
**indicator** library is careful about exactly this — `HistoricalVolatility` takes an
`annualizationFactor` (documenting *"pass e.g. 252*24 for hourly bars"*), and `Parkinson`,
`RogersSatchell`, `YangZhang` all take a configurable `trading_periods`. The **fitness** path
does not. Since there's 15-minute intraday fitting (`crypto_15m.db`) and crypto
short-horizon work at 3h–3d, the same reported Sharpe means materially different things
across resolutions, and cross-resolution comparisons (or any leaderboard mixing them) are
not on a common scale. A 15-minute strategy annualized at `sqrt(252)` understates its
annualized Sharpe by roughly `sqrt(26)`.

**Fix:** one `Metrics.sharpe(returns, rf, periodsPerYear = 252.0)`, have `OrderSim` and
`NmaFitness` delegate to it, and thread the tape's real bar resolution in. Keep 252 as the
default so existing daily results are unchanged.

---

## 5. ⛔ WITHDRAWN — "the fitness path should use `StatsBuiltins`' Kahan/Welford"

**I got this one wrong and am retracting it rather than quietly leaving it on the list.**

The original recommendation (below) was to have the Sharpe path call
`StatsBuiltins.compensatedSum` / `sampleStandardDeviation`. Implementing §4 surfaced why that's
a bad trade here:

1. **It would break a real contract.** The three Sharpe implementations are documented as
   bit-exact with each other and are compared at 1e-9 by `assertNmaParity`. Welford and the
   current two-pass form do not produce identical floats. Changing all three identically is
   possible, but it buys nothing (see 2) while risking the parity gate the whole NMA path
   depends on.
2. **The accuracy gain is illusory at this scale.** The existing code is *already* two-pass
   (mean, then sum of squared deviations) — the numerically sound form, strictly better than the
   naive `E[x²] − E[x]²` that this recommendation was really guarding against. Swapping to
   Welford changes the last bit or two on realistic return series. Kahan on the mean is a
   sub-ULP effect on a few hundred similar-magnitude values.

The original point stands only as an observation that `StatsBuiltins` is the better library for
*new* code. It is not a defect in the fitness path, and "modernize it" would have been change
for its own sake against a live bit-exactness guarantee. Documented in `Metrics.sharpe`'s
docstring so the next reader doesn't re-propose it.

### Original finding (kept for the record)

`StatsBuiltins` has:
- `compensatedSum` (Kahan/Neumaier) — used by its `mean`
- `variance`/`sampleVariance` via **Welford**
- `covariance` via an **online co-moment** update

`Metrics.sharpe`, `OrderSim`'s Sharpe, and `NmaFitness`'s Sharpe each use plain accumulation
(`mean += r`) and a hand-written two-pass variance. The two-pass variance is fine
numerically (it's the *good* form — better than `E[x²]−E[x]²`), so this isn't a correctness
emergency; but the naive `+=` mean has no compensation, and there's no reason for the
objective function to use weaker summation than the library sitting next to it.

Cheapest version of this fix: have the consolidated `Metrics.sharpe` from §4 call
`StatsBuiltins.compensatedSum` and `StatsBuiltins.sampleStandardDeviation`. One change,
all four call sites inherit it.

---

## 6. ✅ FIXED — Two different medians, and the fitness-critical one was the biased variant

`EvolutionEngine.mad()` now delegates both medians to `StatsBuiltins.median`, so the codebase
has one definition again and ε-lexicase's threshold loses its small even-`n` upward bias. The
"raw vs 1.4826-scaled" ambiguity is resolved in the docstring rather than the code: it states
explicitly that raw (unscaled) MAD is intended, because ε-lexicase uses it as a relative
dispersion threshold and not as a σ-estimate — so the next person needing a σ-scaled threshold
knows to apply the constant themselves instead of assuming it's already there.

### Original finding

`EvolutionEngine.mad()` (used as a selection-scale estimate):

```haxe
var med = sorted[Std.int(sorted.length / 2)];      // upper-middle element
var devs = [for (x in sorted) Math.abs(x - med)];
devs.sort(...);
return devs[Std.int(devs.length / 2)];             // same again
```

For **even-length** input this takes the upper of the two central values rather than
averaging them — a small systematic upward bias. `StatsBuiltins.median` does it correctly
(averages for even n). So the codebase has two median definitions and the one inside the
selection path is the less-correct one.

Also worth deciding explicitly: raw MAD is ~0.674σ for normal data. If `mad()` is being
used as a **σ-equivalent scale**, it wants the 1.4826 consistency constant; if it's just a
relative dispersion signal, it doesn't. The docstring says "population MAD" (i.e. raw), so
this may well be intentional — but it's worth a one-line comment saying *which*, because the
next person to use it for a σ-scaled threshold will get it wrong.

Fix: call `StatsBuiltins.median` in both places.

---

## 7. 🟡 `MurmurationRng`: 64-bit-tuned xorshift constants on 32-bit state, plus a cross-target overflow risk

`musescript/murmuration/MurmurationRng.hx` documents itself as **xorshift128+**:

```haxe
x ^= (x << 13); x ^= (x >>> 17); x ^= y ^ (y >>> 26);
return (x + y);
```

Two concerns:

- **Word size.** xorshift128+'s published constants are tuned for **64-bit** state words.
  Haxe `Int` is 32-bit under bitwise ops, so this is a 32-bit variant using 64-bit-derived
  shift triples — not the generator it claims to be, and not one whose statistical properties
  have been characterized. If it needs to stay 32-bit, use a triple actually validated for
  32-bit (e.g. xorshift32's 13/17/5), or move to `haxe.Int64` for a real xorshift128+, or
  swap to a modern small-state generator with good 32-bit variants (PCG32, or SFC32/JSF32
  which are the usual choices at this size).
- **Cross-target divergence.** `(x + y)` on Haxe `Int` **wraps** on JVM/C++ but produces a
  **double** on JS (only forced back to 32 bits by the subsequent `& 0x7FFFFFFF`). This is the
  exact bug class `Rand.imul32` was written to fix (and its comment explains at length) — but
  `MurmurationRng` never got the same treatment. Given how much this project invests in
  bit-exact cross-target parity, a sim-driver RNG that can diverge JS↔JVM is worth closing
  even if Murmuration currently only runs on one target. Use `haxe.Int32` arithmetic here too.

Note the file is admirably explicit that numpy PCG64 bit-parity is a non-goal and only
distributional parity is claimed — so this is about internal consistency and target
portability, not about a broken simulation.

---

## Macro opportunities (robustness guardrails)

`IndicatorRegistryMacro` already directory-scans `indicators/lib/` and emits `spec()` calls,
so adding an indicator is "drop a file in lib/". It **collects** but does not **validate**.

**I went looking for live bugs here first, and found none** — so everything below is a
guardrail to *preserve* properties you currently hold by hand, not a fix for something
broken. Concretely, across all 452 indicators:

```
indicators with a parseable spec():                    452
declared-arity vs args-actually-read mismatches:         0
minArgs > declared args:                                 0
duplicate builtin names:                                 0   (452 distinct)
```

That's a clean bill of health, and it's worth protecting for one specific structural reason:

### M1 — Duplicate-name detection (highest value) ✅ **SHIPPED**

Implemented in two layers:

- **`IndicatorRegistry.ensure`** now throws on a duplicate instead of silently overwriting.
  This is the authoritative check — it sees the real evaluated specs.
- **`IndicatorRegistryMacro.checkDuplicateName`** fails the *build*, for feedback latency.
  It reads the `name:` literal from source text rather than evaluating `spec()` (those bodies
  close over `IndicatorCache` and a live harness, so they can't run at macro time). A source
  scan can only ever *miss* a name, never invent one — so a miss degrades to "the runtime
  check catches it", never to a false build failure. All 452 current specs match the pattern.

**Failure path verified, not assumed:** adding a probe class claiming an already-taken name
(`"adl"`) failed the build with

> `duplicate indicator name "adl" — declared by both Adl and ZzDupeProbe … one of them would be
> silently unreachable. Rename one.`

Probe removed; suite back to 64,144 passing.

*Original rationale below.*
`IndicatorRegistry` does `specs.set(s.name, s)` — a **silent last-wins overwrite**. Combine
that with (a) a directory-scanned registry and (b) the parallel-agent porting workflow used
for these batches, and a future collision is both plausible and silent: one indicator simply
disappears, with no error, and whichever sorted later wins. A macro that fails the build on
a duplicate `name:` is ~15 lines and removes an entire failure mode permanently.

### M2 — `spec()` arity/type coherence
Have the macro check each `spec()`'s declared `args:[…]` / `minArgs` against the
`intArg/floatArg/seriesArg(args, N, …)` indices its `eval` body actually reads, and error on
a mismatch. Currently 452/452 correct by discipline; this makes it correct by construction.
My throwaway script did a regex approximation of this in a few lines — a macro walking the
typed AST would be strictly more reliable.

### M3 — Build-time lint: ban `Array.shift()` in `indicators/lib/`
Once §2's migration lands, a macro that fails the build if a file in `indicators/lib/`
calls `.shift()` keeps the 201-file regression from creeping back one new indicator at a
time. This is the mechanism that makes the migration *stick* rather than decay.

### M4 — Require an explicit annualization factor
After §4, a macro (or a stricter type) that refuses a Sharpe/vol call without an explicit
`periodsPerYear` at any call site outside the daily default would make the resolution
mismatch structurally impossible rather than merely documented.

### M5 — Exhaustive `spec()` ↔ docs ↔ Pine-map coverage
`BuiltinDocsMacro` and `pinescript/translit/BuiltinMap.hx` are separate hand-maintained
surfaces over the same 452 builtins. A macro could report (not necessarily fail on) builtins
that have a `spec()` but no doc entry and no Pine mapping — turning "what's left to map" into
a build-time number instead of a manual audit. That directly feeds the converter-coverage
claim the marketing plan leans on.

---

## Suggested order

1. **§1 `bool()`** — one line, provable bug, fixes a documented-intent violation. Do it first.
2. **M1 duplicate-name macro** — ~15 lines, removes a silent failure mode.
3. **§4 + §5 Sharpe consolidation** — one function, four call sites, fixes both triplication
   and the resolution assumption; also the highest-stakes code in the repo.
4. **§2 RingBuffer migration** — biggest mechanical win, numerically neutral, easy to
   regression-test. Then **M3** to lock it in.
5. **§6 median** — two-line consistency fix.
6. **§3 rolling-quantile structures** — real work; start with the sorted-insert variant on
   the 15 identified files, profile before going further.
7. **§7 MurmurationRng** — `haxe.Int32` for the overflow issue is cheap and worth doing
   regardless; the constant/word-size question deserves its own decision.

*Not covered:* the WASM emitter, WAT assembler, parser/checker internals, and the
Graal/JVM interop layers got only a structural skim — they're large and specialized enough
to deserve their own focused pass rather than a mention here.
