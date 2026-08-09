# Haxe for GraalVM + V8 — JIT Authoring Guide

**Audience:** anyone writing Haxe that must run fast under (a) GraalVM’s host JIT on
JVM bytecode and/or (b) plain V8 (Node / Chromium) on emitted JavaScript — especially
inside `musescript/evo/nma/` and the surrounding fitness / indicator / GraalWasm stack.

**Status:** living doctrine. The empirical claims below were verified by bytecode
decompiles, JIT audits (`scripts/jit_audit_run.sh`), and wall-clock A/Bs on this
codebase. When a claim conflicts with a comment in a hot-path source file, **trust the
source file** and update this guide.

**Sources folded in:**
- In-repo: `NmaNode.hx`, `NmaEval.hx`, `NmaKind.hx`, `RingBuffer.hx`, `GrowableVec.hx`,
  `OrderSim.hx`, `GraalWasmHost.hx`, `JsBackend.hx` / `JsEmitter.hx`, `graal/README.md`,
  `musescript/evo/README.md`, `PLAN_EVO_SPEED.md`, `scripts/jit_audit_run.sh`
- Upstream: [GraalVM Embedding Languages](https://www.graalvm.org/latest/reference-manual/embed-languages/)
  (Engine / Context code caching), [Truffle Monomorphization](https://www.graalvm.org/jdk25/graalvm-as-a-platform/language-implementation-framework/splitting/Monomorphization/),
  [Reporting Polymorphism](https://www.graalvm.org/latest/graalvm-as-a-platform/language-implementation-framework/splitting/ReportingPolymorphism/),
  [Truffle DSL Guidelines](https://www.graalvm.org/latest/graalvm-as-a-platform/language-implementation-framework/DSLGuidelines/),
  [Haxe `@:generic`](https://haxe.org/manual/type-system-generic.html),
  [Haxe `Vector`](https://haxe.org/manual/std-vector.html),
  [V8 Hidden Classes & ICs](https://chromium.googlesource.com/v8/v8/+/main/docs/runtime/hidden-classes-and-ics.md),
  [V8 Fast Properties](https://v8.dev/blog/fast-properties)

---

## 0. One-paragraph contract

You are not writing “clever Haxe.” You are writing **two different machine contracts
from one source**:

| Target | What actually JIT-compiles | What the JIT needs from you |
|---|---|---|
| **GraalVM JVM host** (`build-*-jvm.hxml`) | Ordinary HotSpot/Graal bytecode for Haxe-emitted Java classes | Monomorphic call sites, unboxed `double`/`int`, `final` receivers, `tableswitch` dispatch, escape-analyzable short-lived objects |
| **GraalWasm guest** (`GraalWasmHost`) | Truffle WASM AST under a shared `Engine` | Stable instance reuse, monomorphic Truffle profiles, one Engine / many Contexts |
| **V8** (`build/*.js`, Node) | Ignition → Sparkplug/Maglev → TurboFan on Haxe/JS emit | Stable object shapes (Maps), monomorphic ICs, typed-array numeric buffers, no megamorphic property sites |

NMA is the place where these constraints are intentional, documented, and enforced by
shape. If you add a hot path that violates §1–§4, you are writing against the substrate.

---

## 1. Know which JIT you are talking to

### 1.1 Three layers, three optimization games

```
┌─────────────────────────────────────────────────────────────────────────┐
│  A. Haxe → JVM bytecode  (NMA eval, OrderSim, RingBuffer, GrowableVec)  │
│     Optimized by: Graal / C2 on HotSpot                                  │
│     NOT a Truffle guest. No @Specialization. No automatic splitting.    │
└─────────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────────┐
│  B. Haxe → JS            (JsEmitter strategies, evo-proof, Node benches)│
│     Optimized by: V8 (Ignition → TurboFan)                              │
│     Shapes + ICs are everything. Dynamic is poison.                     │
└─────────────────────────────────────────────────────────────────────────┘
┌─────────────────────────────────────────────────────────────────────────┐
│  C. MuseScript → WASM → GraalWasm  (Fitness "wasm" / CorpusEvoRun)      │
│     Optimized by: Truffle WASM + host Graal inlining across polyglot    │
│     Engine-shared code caches; instance reuse keeps profiles mono.      │
└─────────────────────────────────────────────────────────────────────────┘
```

**Critical inversion (from `NmaNode.hx`):** layer A is *not* a Truffle language.
The instinct to put a virtual `execute()` on every AST node — the classic Truffle
self-optimizing interpreter pattern — is **actively wrong** here. Truffle gets
per-call-site specialization and monomorphization-via-splitting; plain JVM bytecode
over 16 subclasses at one call site gets a megamorphic vtable and a blocked escape
analysis. We simulate Truffle’s “interpret then specialize” with an explicit
`kernel: NmaKernel` slot (tiered execution), not with virtual methods.

### 1.2 What “monomorphic” means on each layer

| Layer | Monomorphic means | Megamorphic means |
|---|---|---|
| **A (JVM)** | One concrete receiver type (or one `switch` case body after `cast`) at a hot call site → Graal can inline and scalar-replace | Many concrete types at one virtual call → vtable, no inline, returned objects escape |
| **B (V8)** | One Hidden Class (Map) seen at an IC site → TurboFan emits map-check + fixed offset load | >~4 Maps → global stub cache; TurboFan often refuses to optimize the containing function |
| **C (Truffle)** | One specialization / one AST clone per call site after splitting | Generic slow specialization active; without `@ReportPolymorphism` the runtime may never split |

Upstream Truffle monomorphization ([Monomorphization Use Cases](https://www.graalvm.org/jdk25/graalvm-as-a-platform/language-implementation-framework/splitting/MonomorphizationUseCases/))
is the *guest*-language version of what we hand-roll on layer A with kind-switches and
what V8 does on layer B with Maps/ICs. Same idea, three mechanisms.

### 1.3 Warmup is part of the contract

From `graal/README.md` (KestrGraal, measured 2026-07-15):

- Cold first call after module load: **~1.3s** (eval + JIT warmup)
- Warm subsequent: **~11.7ms**/backtest including gRPC (~720k bars/sec on 8419 SPY bars)

If your microbench does not warm the same call shape for tens of thousands of iterations
before measuring, you are timing the interpreter / C1 / Ignition, not the steady-state
JIT you claim to care about. `EvoBench` and `IndicatorTapeBench` exist for this reason.
`scripts/jit_audit_run.sh` exists so “felt slower” becomes a deopt/inline log.

---

## 2. Dispatch discipline — the NMA law

### 2.1 The law (memorize this)

> Hot evaluation of a heterogeneous node tree on the **JVM target** MUST dispatch via
> a central `switch (node.kind)` + typed `cast`, never via a virtual method shared by
> all leaf subclasses.

Reference shape: `NmaEval.evalScalar` / `evalBool` / `evalSeries`, and `NmaBijection`.

```haxe
// GOOD — tableswitch + monomorphic case bodies (Graal inlines each arm)
var col:GrowableVec<Float> = switch (node.kind) {
	case KArith:
		var a = (cast node : NmaKArith);
		arith(a.op, evalScalar(a.a, ctx), evalScalar(a.b, ctx), ctx.n);
	case KLookback:
		var l = (cast node : NmaKLookback);
		lookback(evalSeries(l.s, ctx), l.n, ctx.n);
	// ...
};

// BAD — megamorphic virtual call over ~16 subclasses at ONE site
node.eval(ctx);           // never
visitor.visit(node);      // never on the per-bar / per-column hot path
Std.isOfType(node, ...)   // cascade of instanceof — worse than tableswitch
```

Why Haxe’s enum `switch` wins: `NmaKind` is a flat enum; the JVM target lowers the
switch to a **`tableswitch`** on the constructor ordinal (O(1) jump table), not a
chain of `instanceof`. Each arm then holds a concrete `cast` to a **`final`** leaf
class, so subsequent field loads and method calls are monomorphic and inlinable.

### 2.2 Concrete-class hygiene that makes the switch pay off

From `NmaNode`’s Graal doctrine block — non-negotiable for new NMA leaves:

1. **Every leaf class is `final`.** Enables post-`cast` devirtualization.
2. **Every structural field is `final`.** Constant-foldable after construction; mutation
   of tree shape goes through explicit edit + `invalidate()`, not field reassignment of
   children you pretend are immutable.
3. **No boxed optional primitives on hot fields.** Prefer `Float`/`Int` with sentinels
   (`Math.NaN`, `-1`) over `Null<Float>` / `Null<Int>` (those become `java.lang.Double` /
   `Integer` and defeat escape analysis — see `OrderSim.pendingQty`).
4. **Discriminant is a cheap `final NmaKind kind`.** Set once in the leaf ctor. Never
   recompute via `Std.isOfType`.

### 2.3 Allocation-free structural walks

| Primitive | Use when | Allocates? |
|---|---|---|
| `childCount()` / `childAt(i)` | Per-generation credit, dirty propagation, any hot walk | **No** |
| `childNodes():Array<NmaNode>` | Tests, tooling, cold dumps | **Yes** — megamorphic + array mint |

Override only `childCount`/`childAt` in branching leaves. `childNodes` is derived and
cold. Ordering must match enum constructor argument order so NMA walks visit the same
subtree order as enum recursion (`Canonical`, `Simplify`, bijection round-trips).

### 2.4 The `kernel` slot — our stand-in for Truffle specialization

`NmaKernel` is an empty marker interface on purpose (P0). Semantics (spec §5.3):

1. Interpret via the central kind-switch until a subtree shape is hot.
2. Compile a fused monomorphic evaluator for that shape (WASM-fused genome and/or a
   JVM `@:build` specialized walker).
3. Store it in `node.kernel` and short-circuit the interpreter.

This is **tiered execution attached to the node**, not a language-runtime feature.
Until a concrete kernel emitter exists, leave the slot typed (`Null<NmaKernel>`, never
`Null<Dynamic>`) so it stays greppable and type-safe.

`invalidate()` clears `kernel` with the rest of the memo state — any structural edit
must drop the specialized code.

### 2.5 When virtual methods *are* fine

Cold paths. GUI. Serialization. One-shot CLI. Test helpers. Anything that does not
run per-bar, per-column, or ~O(pop × gens × nodes) per evolution step.

If you are unsure: ask whether Graal would see the call site with **many concrete
receivers in one feedback profile**. If yes → kind-switch. If no → write the readable
code.

---

## 3. Unboxed numeric storage — `@:multiType` or GTFO

### 3.1 The JVM boxing trap (empirically verified)

A plain `class Buf<T>` backed by `Array<T>` / `haxe.ds.Vector<T>` **boxes every
`Float` as `java.lang.Double`** on the JVM target, because generic `T` erases to
`Object`. Decompiled probes in this repo confirmed:

- `@:generic` *can* emit a real `double[]` — **but only** when the concrete type is
  visible at a non-generic instantiation site (e.g. a field typed `RingBuffer<Float>`).
- `@:generic` **does not** propagate through an abstract’s own constructor: the
  abstract’s type parameter is already erased there.
- Therefore the winning pattern is **`@:multiType`** (same mechanism as `Map<K,V>`):
  pick between **independently hand-written** concrete impls at compile time.

Canonical implementations:

- `musescript/indicators/RingBuffer.hx` — fixed-capacity rolling window
- `musescript/indicators/GrowableVec.hx` — unbounded series / equity / NMA columns

Float fast path = **plain non-generic class** whose field is `haxe.ds.Vector<Float>` →
true `double[]` on JVM (`push(D)` / `at(I)D` in bytecode).

### 3.2 How to add a new primitive buffer type

```haxe
@:multiType(@:followWithAbstracts T)
abstract FastVec<T>(IFastVec<T>) {
	public function new(?cap:Int = 8);
	public inline function push(v:T):Void return this.push(v);
	@:arrayAccess public inline function at(i:Int):T return this.at(i);
	// ...

	@:to static inline function toFloat(t:IFastVec<Float>, ?cap:Int = 8):FastFloatImpl
		return new FastFloatImpl(cap);

	@:to static inline function toGeneric<T>(t:IFastVec<T>, ?cap:Int = 8):FastGenericImpl<T>
		return new FastGenericImpl(cap);
}

class FastFloatImpl implements IFastVec<Float> {
	var data:haxe.ds.Vector<Float>; // ← concrete Float at THIS class's definition
	// ...
}
```

Do **not** try to “just use `@:generic` on the abstract.” Do **not** store hot series
in `Array<Float>` on the JVM path and expect unboxed math. Do **not** invent a third
ad-hoc container without measuring — see `SymbolSelector.hx`’s TODO: the shared
hyper-opt vector type should land *once* and be reused.

### 3.3 Indexed loops only — `for..in` always boxes on JVM

Verified by decompilation: Haxe’s `for (v in window)` on the JVM target normalizes
custom iterators through `java.util.Iterator.next():Object`, so **even** an unboxed
`next():Float` on the concrete iterator boxes on the bridge.

```haxe
// BAD on hot scans — boxes every element on JVM
for (v in window) if (v < min) min = v;

// GOOD — primitive loop, zero boxing
for (i in 0...window.length) {
	var v = window.at(i); // or window[i]
	if (v < min) min = v;
}
```

This is the single most common indicator-library footgun. Prefer indexed form in
anything that runs every bar.

### 3.4 Grow vs ring — pick the right shape

| Need | Type | Indexing |
|---|---|---|
| Rolling window of fixed `period` | `RingBuffer<Float>` | `at(0)` = newest, `at(length-1)` = oldest |
| Full-tape column / equity curve | `GrowableVec<Float>` | `at(0)` = first pushed (Array-like) |
| Interop / JSON / public typedef locked to `Array` | `toArray()` **once** at the boundary | Pay O(n) once, not every push |

`GrowableVec` grows by capacity-doubling + `Vector.blit` → `System.arraycopy` on JVM
(native handle copy, not per-element box). Materialize with `toArray()` only at
boundaries (`GraalWasmHost` equity handoff is the textbook site).

### 3.5 V8 twin of the same idea

On the JS target, `haxe.ds.Vector<Float>` lowers toward a dense array; for WASM memory
and host numeric kernels prefer **`Float64Array` / `Float32Array` views** over plain
`Array` of numbers (see `StrategyWasmBackend` / `WasmBackend`). V8’s elements kinds
specialize hard on typed arrays; packing OHLCV as boxed JS Numbers in a holey array
is leaving TurboFan on the table.

---

## 4. Hot call edges — kill boxing at the boundary

### 4.1 `Null<Float>` is a silent throughput tax

`OrderSim`’s omitted-qty sentinel is **`Math.NaN`**, not `null`:

> null forces every JVM-target call into `long`/`short`/`executeLong`/`executeShort`
> to box qty as `java.lang.Double`, defeating escape analysis on this exact per-bar
> hot path — found by JIT audit (`PLAN_EVO_SPEED.md`).

Rule: if a `Float` argument is optional on a per-bar path, encode absence with a
**bit-pattern sentinel that remains a primitive** (`NaN`, `±Infinity`, or a documented
out-of-domain int like `-1`), and document it next to the field.

### 4.2 `Dynamic == false` is a hard cast bomb

`FourierMath.boolArg` documents a GraalVM indicator-bench finding: comparing
`Dynamic == false` compiles to a **hard Double→Boolean cast** on the JVM target and
blows up (same strictness class as the garch11 arg bug). Resolve optionals with
`Std.isOfType` branches, never with equality against a Bool literal on `Dynamic`.

```haxe
// BAD
if (args[i] == false) ...

// GOOD
if (Std.isOfType(v, Bool)) return (v : Bool);
if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float) != 0.0;
```

### 4.3 Reuse argument arrays at polyglot boundaries

`GraalWasmHost.StrategyInstance` pre-allocates a `NativeArray` for `onBar.execute` and
mutates `arg[0] = i` each bar — no per-bar allocation of the args vector. Same spirit
as JsBackend’s arity-specialized `invoke0`…`invoke4` (no args `Array` for ≤4 arity).

Any host→guest or guest→host call in a tight loop should:

1. Allocate the carrier **once** outside the loop.
2. Mutate slots in place.
3. Keep the executable/`Value` handle stable (don’t re-`getMember` every iteration if
   the export map is fixed).

### 4.4 Materialize once at the seam

```haxe
// GraalWasmHost — GrowableVec stays unboxed through the whole sim;
// Array appears exactly once for Metrics / result typedefs.
var eqArr = sim.equity.toArray();
```

Crossing a seam (`Array` ↔ `GrowableVec`, Haxe ↔ `Value`, JS ↔ typed array) more than
once per run is usually a design smell.

---

## 5. GraalVM host / Polyglot / Truffle guest rules

### 5.1 Engine vs Context (upstream + our practice)

From GraalVM *Embedding Languages* — **code caching across multiple contexts** — and
from `graal/README.md` / `GraalWasmHost`:

| Object | Lifetime | Sharing |
|---|---|---|
| **`Engine`** | Process (or long-lived pool) | **Share one** across threads so Truffle code caches persist |
| **`Context`** | One per worker thread | Do **not** share across threads; create with `.engine(sharedEngine)` |
| **Module `Value`** | Cached per `wasm_path` on the thread | Skip re-`eval` on repeated artifacts |
| **`StrategyInstance`** | Reused across many `run()` calls | Keeps Truffle profiles **monomorphic**; packs OHLCV once |

```haxe
// GraalWasmHost pattern
public function new(?sharedEngine:Engine, ?options:Map<String, String>) {
	ownsEngine = sharedEngine == null;
	if (ownsEngine) {
		var b = Engine.newBuilder(...).allowExperimentalOptions(true);
		// ...
		engine = b.build();
	} else engine = sharedEngine;
	ctx = Context.newBuilder(...).engine(engine).build();
}
```

KestrGraal is the production shape of this: one Engine for process lifetime, one
Context per worker, per-thread module cache.

### 5.2 Memory ABI hygiene (GraalWasm)

From `graal/README.md`:

- Prefer **preloaded** mode for offline backtests (`configure_tape` + `on_bar(i)`).
- Pack OHLCV with Graal buffer APIs (`writeBufferDouble(LITTLE_ENDIAN, …)`).
- **Reacquire** `exports.memory` after `ensure_capacity` / `memory.grow`.
- JDK 24+: `--sun-misc-unsafe-memory-access=allow` for Truffle / `sun.misc.Unsafe`.
- Pin `org.graalvm.polyglot:polyglot` + `wasm-community` to the installed GraalVM version.

### 5.3 Truffle options — measure, don’t folklore

`EvoBench` currently experiments with
`engine.LastTierCompilationThreshold=2000000000` (effectively disables last-tier
Truffle WASM JIT). That is an **A/B knob**, not a free lunch — see `PLAN_EVO_SPEED.md`
P4. Rules:

1. Change one engine option at a time.
2. Warm both configs equally.
3. Keep wall-clock **and** `jit_audit_run.sh` summaries.
4. Prefer Engine reuse + instance reuse over exotic thresholds until those are saturated.

### 5.4 What Truffle docs imply for *our* non-Truffle Haxe

We do not author Truffle DSL nodes in Haxe. But the *lessons* transfer:

| Truffle guidance | Haxe / NMA analogue |
|---|---|
| Keep nodes monomorphic; split polymorphic ones | Kind-switch + eventual `NmaKernel` per hot shape |
| `@ReportPolymorphism.Megamorphic` on slow generic specializations | Don’t leave a “slow Dynamic fallback” on a hot site; make the slow path a separate cold function |
| Avoid mixing shared/non-shared inline profiles carelessly | Don’t share mutable scratch buffers across concurrent workers without clear ownership |
| Minimize PE code size | Keep kind-switch arms small and `inline`-friendly; extract cold error paths |

---

## 6. V8 / plain-JS authoring rules

### 6.1 Shapes (Hidden Classes) are your type system at runtime

V8 attaches a **Map** (hidden class) to every object. Property access ICs record which
Maps appear at each site:

| IC state | Maps seen | TurboFan behavior |
|---|---|---|
| Monomorphic | 1 | Map check + fixed-offset load — **this is the goal** |
| Polymorphic | 2–4 | Linear map checks |
| Megamorphic | >~4 | Global stub cache; often **blocks** optimizing the function |

Authoring rules that keep Maps stable:

1. **Initialize properties in a fixed order** in constructors / object literals.
2. **Don’t delete** properties (`delete obj.x` → dictionary mode; ICs die).
3. **Don’t add properties later** on only some instances of a “class.”
4. Prefer **constructor functions / Haxe classes** over ad-hoc `{}` mutation soups for
   anything that appears in a hot loop.
5. Keep prototype chains shallow and stable for hot method calls.

Haxe already helps: a `class` with a fixed field set emits a stable constructor shape.
`Dynamic`, `Reflect.field` / `Reflect.setField` in a hot loop, and building result
objects with different keys per branch are how you undo that help.

### 6.2 Arity-specialized calls (our JsBackend doctrine)

`JsEmitter` emits `api.invokeN` for ≤4 args; `JsBackend` keeps per-arity plain-object
tables of fixed-arg closures:

- No args `Array` allocation on the hot builtin path
- No string `switch` after the first resolve (memoized per name)
- `api.set` of a function invalidates the memo so local shadowing still wins

When extending the JS runtime:

- Add hot builtins to the **fast tables**, not only to `dispatchBuiltin`.
- Keep the slow path bit-exact with the fast path (coercions, defaults).
- Do not “simplify” by funneling everything through `invoke(name, args:Array)`.

### 6.3 Numeric kernels on V8

From `IndicatorKernels.hx` / WASM backends:

- Tight `while` / indexed `for` over contiguous float storage
- Prefer typed-array views for anything that also touches WASM memory
- Avoid boxing through `Array<Dynamic>` or per-iteration object literals
- Keep branch patterns predictable (sorted uncommon cases out of the inner loop)

### 6.4 Things that look cute and murder TurboFan

- `arguments` object materialization
- `eval` / `new Function` in hot paths
- Megamorphic `obj[key]` where `key` is unboundedly many strings
- Mixing element kinds in one array (holes, then doubles, then objects)
- Changing the shape of a cached API object after warmup (`delete` / random new fields)

---

## 7. Authoring inside `musescript/evo/nma/` specifically

### 7.1 Dual representation — do not collapse it

| Form | Role | Mutable? |
|---|---|---|
| `BoolNode` / `ScalarNode` / `SeriesNode` enums | Canonical term: serialize, `Canonical` keys, elites, Simplify | Immutable values |
| NMA classes | Working copy: credit, partial-eval memo, `kernel`, dirty keys | Mutable |

**Only** `NmaBijection` crosses the boundary. Round-trip is structure-preserving and
**working-state-lossy** (credit/memo/kernel intentionally dropped). Never store elites
as NMA graphs; never run attribution against enum trees if you need node-local memo.

### 7.2 Columnar eval, not interleaved

`NmaEval` builds full-tape `GrowableVec<Float>` columns. Bools are `0.0` / `1.0`
(`TRUE`/`FALSE` inlines). Indicators **only** through `NmaIndicatorProvider` →
`EngineIndicatorProvider` → real `TradeBuiltins` (parity discipline).

`KFeature` genomes that need interleaved position state are refused at the fitness
boundary — don’t “just add a virtual feature hook” without an epoch story.

### 7.3 Epochs and memo

- `NmaEpoch` interns an evaluation signature (tape + costBps + params…).
- `node.evalEpoch == ctx.epoch.id && node.lastSeries != null` → memo hit.
- Structural edits call `invalidate()` (clears key, epoch, series, kernel) and must
  dirty **up the spine** when P1+ dirty propagation is wired.

This is how PLAN_EVO_SPEED’s attribution-oracle whale collapses from “full backtest
per ablation” into shared subtree columns.

### 7.4 Adding a new node kind — checklist

1. Add tag to `NmaKind` (name mirrors the enum constructor).
2. Add `final class Nma… extends NmaSeries|NmaScalar|NmaBool` with `final` fields.
3. Wire `NmaBijection` both directions.
4. Wire `NmaCanonical` / `NmaEval` / credit walk with **kind-switch arms**, not methods
   on the base class.
5. Override `childCount`/`childAt` if branching; never rely on `childNodes` in hot code.
6. Add round-trip + parity tests (`TestNma*`).
7. If the arm does numeric work, read/write `GrowableVec<Float>` with indexed loops.
8. Update this guide if you invent a new dispatch pattern (you shouldn’t).

### 7.5 Import hygiene

`NmaKind` constructor names collide with evo enum constructors. In modules that import
both, alias: `import musescript.evo.nma.NmaKind as NmaK;`. Inside `switch (node.kind)`
the switch subject’s type resolves patterns — collisions don’t apply there.

---

## 8. Cross-cutting Haxe target craft

### 8.1 `@:generic` vs `@:multiType` vs erasure

| Tool | Use when | Pitfall |
|---|---|---|
| Default generics | Cold / reference-typed data | `Float` boxes on JVM |
| `@:generic` | Concrete type visible at construction; you want monomorphized methods | Doesn’t pierce abstract ctors; code size grows |
| `@:multiType` | Primitive-fast containers (`RingBuffer`, `GrowableVec`) | Must hand-write Float impl; more boilerplate |
| `haxe.ds.Vector<T>` | Fixed-length native array backing | Still boxes if `T` is a class type param erased to Object |

Haxe manual: `@:generic` emits distinct classes per type argument (e.g.
`MyValue_Float`) at the cost of size — use it for hot monomorphic helpers, not as a
substitute for `@:multiType` containers.

### 8.2 `inline` — earn it

Inline small, stable helpers on hot paths (`stamp`, getters, sentinel checks). Do not
inline megakilobyte kind-switch arms into every caller — you will trip
“hot method too big” / “already compiled into a big method” in JIT audit summaries.

### 8.3 Prefer value-like `@:structInit` for cold records

Fine for configs, descriptors, cache entries. Not a substitute for unboxed float
vectors on the bar loop.

### 8.4 `#if js` / `#if java` / `#if jvm` — localize, don’t fork architecture

Target-specific *backends* (typed arrays, `NativeArray`, unsafe) belong behind small
seams. The **algorithm** (kind-switch, columnar eval, NaN sentinels) should be shared
so parity tests mean something.

---

## 9. Measure — standing practice

### 9.1 JIT-audited JVM runs

From `musescript/evo/README.md`:

```bash
scripts/jit_audit_run.sh build/jvm/evo-bench.jar musescript.evo.graal.EvoBench --pop 40 --gens 10
```

Writes `build/graal/jit-audit/<main>/summary.txt` with:

- Top deopt methods / reasons
- `haxe.jvm.*` / `musescript.*` deopt sites called out (the ones you can fix)
- Top inlining rejection reasons (`too large`, `virtual call`, `receiver not constant`, …)
- Snapshot of `evo_bench_report.json` when present

**Hard rule:** never rebuild `build/jvm/corpus-evo.jar` (or point the auditor at it)
while a live `CorpusEvoRun` has that jar open — JVM lazy-loads classes mid-run
(`PLAN_EVO_SPEED.md`). Check live java processes first.

### 9.2 What to look for in summaries

| Signal | Likely cause | Fix direction |
|---|---|---|
| `virtual call` / `receiver not constant` on your method | Megamorphic dispatch | Kind-switch / `final` / split call sites |
| `class_check` deopts | Unstable receiver types | Same |
| `null_check` storms on a hot Float path | `Null<Float>` / unexpected nulls | Sentinels, non-null invariants |
| `too large` / `hot method too big` | Over-inlined or giant switch | Extract cold paths; split stages |
| Wall-clock regression with clean JIT log | Algorithmic whale (oracle, parse) | `PLAN_EVO_SPEED` — don’t “optimize” the wrong layer |

### 9.3 V8 measurement

- Warm deliberately before timing.
- Use `--trace-ic` / `--trace-deopt` (Node flags vary by version) when chasing shape
  bugs — analogous spirit to `jit_audit_run.sh`.
- Prefer comparing **same-seed** A/Bs for evo (bit-identical per-gen lines when the
  phase claims zero behavior change).

### 9.4 Don’t optimize myths

`PLAN_EVO_SPEED` measured the whale: attribution oracle full-tape interp, not the
GraalWasm fitness workers. JIT-tuning Truffle thresholds while the main thread
re-parses 1500 genomes/gen is rearranging deck chairs. Profile wall time first; then
open the JIT log.

---

## 10. Anti-pattern catalog (print and tape to the monitor)

1. **Virtual `eval` / visitor on NMA hot path** — megamorphic on JVM.
2. **`Array<Float>` as the per-bar workhorse on JVM** — boxed Doubles.
2b. **Reading a structural typedef's numeric fields inside a bar loop** — `bar.close` on a
    `typedef Bar = { close:Float, … }` is `haxe.jvm.Jvm.readField(Object, String)`, a string-keyed
    dynamic lookup returning a boxed `Double`. See §34.
3. **`for (v in ring)` in indicator updates** — boxes via `Iterator` bridge.
4. **`Null<Float>` optional args on OrderSim-like edges** — kills escape analysis.
5. **`Dynamic == false` / loose Dynamic compares** — hard cast explosions on JVM.
6. **New Graal `Context` or WASM `newInstance` per backtest** — profile reset + alloc.
7. **Re-`eval` WASM module every call** — pay the 1.3s forever.
8. **Per-bar `toArray()` / object literal / args array** — GC + shape churn.
9. **Ad-hoc `Reflect.*` in JS hot loops** — megamorphic ICs.
10. **Deleting / late-adding fields on cached API objects** — dictionary mode.
11. **Funneling all JS builtins through `invoke(name, args:Array)`** — undoes arity fast path.
12. **Optimizing Truffle knobs before caching the oracle** — wrong whale.
13. **Rebuilding jars under a live evo process** — corrupted runs.
14. **Storing elites as NMA graphs / evaluating enums with node-local memo assumptions** —
    dual-rep confusion.
15. **Inventing a second float vector type without replacing `Array<Float>` call sites** —
    see `SymbolSelector` TODO; one shared type, everywhere.

---

## 11. Positive pattern catalog (steal these)

| Pattern | Reference |
|---|---|
| Kind-switch + `cast` + `final` leaves | `NmaEval`, `NmaBijection`, `NmaCanonical` |
| `@:multiType` Float impl over `Vector<Float>` | `RingBuffer`, `GrowableVec` |
| Indexed scans | Every hot indicator loop |
| NaN qty sentinel | `OrderSim.pendingQty` |
| Engine share + instance reuse | `GraalWasmHost`, KestrGraal |
| Pack tape once; mutate `NativeArray` args | `StrategyInstance` |
| Arity-specialized invoke0–4 | `JsEmitter` + `JsBackend` |
| Columnar memo by epoch | `NmaEval` + `NmaEpoch` |
| Typedef fields hoisted to per-tape unboxed columns | `NmaBarColumns` + `NmaFitness.runPrepared` |
| `childCount`/`childAt` walks | `NmaNode` |
| JIT audit before claiming a win | `scripts/jit_audit_run.sh` |
| Typed `NmaKernel` slot for future fusion | `NmaKernel.hx` |

---

## 12. Worked micro-examples

### 12.1 JVM — columnar arith arm (sketch)

```haxe
static function arith(op:String, a:GrowableVec<Float>, b:GrowableVec<Float>, n:Int):GrowableVec<Float> {
	var out = new GrowableVec<Float>(n);
	var i = 0;
	while (i < n) {
		var x = a.at(i);
		var y = b.at(i);
		var z = switch (op) {
			case "+": x + y;
			case "-": x - y;
			case "*": x * y;
			case "/": y == 0.0 ? Math.NaN : x / y;
			default: Math.NaN;
		};
		out.push(z);
		i++;
	}
	return out;
}
```

Notes: indexed reads, local `while`, `switch` on a string op is acceptable at column
granularity (once per node, not once per micro-op inside a megamorphic virtual). If
profiles show the op switch hot and polymorphic across many ops at one site, split
per-op functions and dispatch once outside the loop.

### 12.2 JS — keep a monomorphic point shape

```haxe
class Pt {
	public var x:Float;
	public var y:Float;
	public function new(x:Float, y:Float) {
		this.x = x;
		this.y = y;
	}
}

// GOOD — all Pts share one Map
function clear(p:Pt):Void { p.x = 0; p.y = 0; }

// BAD — some code paths add p.z → new Map → polymorphic IC at every p.x load
```

### 12.3 Polyglot — reuse

```haxe
// once
var host = new GraalWasmHost(sharedEngine);
var module = host.loadModuleFile(path);
var inst = host.instantiate(module, strings);

// many
for (g in population) {
	var r = inst.run(bars, paramsFor(g)); // profiles stay warm
}
```

---

## 13. Roadmap hooks (don’t pretend they’re done)

- **`NmaKernel` emitters** — stage-4 fused evaluators; empty interface today.
- **Shared hyper-opt vector type** — `FloatSeries` (`musescript/indicators/FloatSeries.hx`) is
  wired into the NMA tape columns (`NmaBarColumns`, §34); `SymbolSelector` and the indicator
  feeds are still owed.
- **Object pooling** — only if measured to help; naive pools often *hurt* Graal escape
  analysis (same TODO warns). Prefer short-lived scalars the JIT can stack-allocate.
- **Auxiliary Engine Caching / PGO** — CE vs Enterprise licensing; see `graal/README.md`.
- **LastTier A/B** — `PLAN_EVO_SPEED` P4; audit before and after.

---

## 14. Quick author checklist (PR self-review)

**Before you merge hot-path Haxe:**

- [ ] Which layer? (JVM host / V8 / GraalWasm guest) — stated in the PR
- [ ] Dispatch: kind-switch or proven-monomorphic call?
- [ ] Numeric storage: `GrowableVec`/`RingBuffer`/`Vector`/`Float64Array`, not boxed `Array`?
- [ ] Loops: indexed, not `for..in`, on float buffers?
- [ ] Optionals: NaN/`-1` sentinels, not `Null<Float>`, on hot edges?
- [ ] No new `Dynamic` compares; no `Reflect` in inner loops?
- [ ] Graal: Engine shared? Instance reused? Memory reacquired after grow?
- [ ] JS: stable shapes? Fast-table builtin if ≤4 arity?
- [ ] NMA: bijection + eval + canonical arms updated together?
- [ ] Measured: `jit_audit_run.sh` or equivalent warm A/B attached?

---

## 15. Glossary

| Term | Meaning here |
|---|---|
| **IC** | Inline Cache — per-site feedback for property/call shapes (V8) or analogous JVM profiling |
| **Map / Hidden Class** | V8’s object-shape descriptor |
| **Monomorphic** | One stable type/shape at a site |
| **Megamorphic** | Many types/shapes; JIT gives up on the fast path |
| **tableswitch** | JVM bytecode jump table; what Haxe enum switches become |
| **Escape analysis** | JIT proves an object doesn’t leave a method → scalar replace / stack allocate |
| **Engine / Context** | Graal Polyglot process-level code cache vs thread-level execution sandbox |
| **NMA** | Neural Muse AST — stateful class working copy of evo genomes |
| **Kind-switch** | `switch (node.kind)` + `cast` dispatch law |
| **Columnar eval** | Full-tape column per node, memoized by epoch |
| **Whale** | Dominant wall-time consumer (today: attribution oracle, not WASM workers) |

---

## 16. Reading order for new contributors

1. This file (§0–§2, §10–§11)
2. `NmaNode.hx` header (Graal doctrine)
3. `NmaEval.hx` + `NmaKind.hx` + one leaf file (`NmaScalar.hx`)
4. `RingBuffer.hx` + `GrowableVec.hx` headers (boxing science)
5. `OrderSim.hx` NaN sentinel comment
6. `GraalWasmHost.hx` + `graal/README.md`
7. `JsBackend.hx` arity fast path + `JsEmitter.hx` `ECall` arm
8. `PLAN_EVO_SPEED.md` (where time actually goes)
9. `scripts/jit_audit_run.sh` (run it once on `EvoBench`)
10. Upstream Graal embedding + Truffle monomorphization + V8 hidden-classes docs

---

## 17. Decision trees (when stuck)

### 17.1 “How do I dispatch over node kinds?”

```
Is this on a per-bar / per-column / per-ablation hot path?
├─ NO  → virtual method / visitor / pattern match however you like
└─ YES → JVM host or V8?
         ├─ JVM host (NMA, OrderSim, indicators)
         │    └─ switch (node.kind) + cast to final leaf  [MANDATORY]
         └─ V8 (emitted JS strategy / JsBackend)
              └─ stable class shapes + arity-specialized invoke;
                 avoid Dynamic / Reflect in the inner loop
```

### 17.2 “How do I store floats?”

```
Fixed rolling window?
├─ YES → RingBuffer<Float>  (+ indexed scan, never for..in on hot path)
└─ NO  → Grows to tape length?
         ├─ YES → GrowableVec<Float>
         └─ NO  → Fixed known length?
                  ├─ YES → haxe.ds.Vector<Float> (or @:multiType twin)
                  └─ Interop boundary only → Array<Float> via toArray() ONCE
```

### 17.3 “GraalWasm feels slow”

```
Are you newInstance() / eval()'ing per backtest?
├─ YES → stop; reuse StrategyInstance + shared Engine  [first fix]
└─ NO  → Is the whale actually on the main-thread oracle?
         ├─ YES → PLAN_EVO_SPEED P0 caches (not Truffle knobs)
         └─ NO  → Warm A/B LastTier / workers; jit_audit_run.sh
```

### 17.4 “JS bench regressed after a refactor”

```
Did object shapes change? (new fields, delete, per-branch keys)
├─ YES → restore monomorphic constructors
└─ NO  → Did hot calls go through invoke(name, args[])?
         ├─ YES → restore invoke0..4 / fast tables
         └─ NO  → typed arrays → plain Array? reverse it
```

---

## 18. Kernel loop shapes (what “fast” looks like in source)

`IndicatorKernels` is the muse-script reference for **math-only** tape kernels: one
`while (i < n)`, locals for running state, no harness objects, no per-bar allocations.

Transferable rules for Haxe that must JIT well on **both** JVM and V8:

1. **Hoist invariants** (`alpha`, window lengths) outside the bar loop.
2. **Keep the carried state in scalars / unboxed buffers**, not heap objects rebuilt
   each bar.
3. **Prefer `while` with a manual index** over iterator protocols when scanning floats.
4. **Branch on uncommon cases with predictable polarity** (fill path vs steady-state
   path for RSI/ATR warmups — same shape as RingBuffer filling vs full).
5. **Accumulate into a register-like local** (`sum`, `ema`, `atr`) when the consumer
   only needs a reduction; don’t mint per-bar result objects unless required.
6. **When you need the full series**, push into `GrowableVec<Float>` (JVM) or a
   pre-sized typed array (JS), never `arr.push` into a holey growing Array if you can
   avoid it on the hottest path.

MuseScript source that looks like that kernel also lowers cleanly through
`MathCompiler` / WASM backends — the authoring aesthetic is the optimization.

---

## 19. Bijection as the canonical kind-switch template

`NmaBijection` is not “just conversion.” It is the **reference shape** every new hot
walker must copy:

```haxe
public static function scalarFromEnum(n:ScalarNode):NmaScalar {
	return switch (n) {
		case KConst(v): new NmaKConst(v);
		case KArith(op, a, b): new NmaKArith(op, scalarFromEnum(a), scalarFromEnum(b));
		// ...
	};
}
```

And the inverse NMA→enum side is a `switch (node.kind)` with casts — identical control
flow to `NmaEval`. If your new pass cannot be written in that shape, it does not belong
on the hot path.

Contract reminders:

- `toEnum(fromEnum(x))` is structurally identical for `Canonical` / `Expand`.
- Round-trip **drops** credit, memo, kernel — by design.
- Transparent holes (`BHole`/`KHole`) are preserved, not unwrapped.

---

## 20. Escape analysis — write code the JIT can stack-allocate

Graal’s escape analysis (and HotSpot’s) can scalar-replace objects that never leave a
compiled method. You help it by:

| Do | Don’t |
|---|---|
| Return primitives / write into caller-owned buffers | Return freshly boxed `Null<Float>` wrappers |
| Keep short-lived `@:structInit` records in tight scopes | Store them in static caches “just in case” |
| Use `final` fields so the JIT trusts layout | Mutate identity fields after publication to other threads |
| Prefer `inline` tiny wrappers that disappear | Build builder-pattern object graphs per bar |

Pooling is **not** automatically better: a hand-rolled pool often *forces* objects to
escape into the pool’s array, defeating scalar replacement. Measure; the
`SymbolSelector` TODO explicitly warns against pools that cost Graal optimizations.

---

## 21. Concurrency notes (evo workers)

- **One `Context` per worker thread**; never share Contexts across threads.
- **Share one `Engine`** so Truffle compilations amortize.
- **Don’t share mutable NMA graphs** across workers without a clear ownership /
  copy protocol — credit and memo are node-local mutable state.
- **Canonical enums / structural keys** are the safe cross-thread identity.
- Jar rebuild rule still applies under parallel runs: don’t clobber a jar a live
  process is loading from.

---

## 22. Parity & correctness under optimization

Speed without bit-exact parity is a bug in this codebase. Standing expectations:

| Change class | Required proof |
|---|---|
| Zero behavior change (P0 caches, container swap) | Same-seed evo lines identical; unit suite green |
| NMA eval vs Expand/TradeBuiltins | Differential tests on crossover/crossunder/rising/falling/NaN |
| JsBackend fast tables | Case-for-case mirror of `dispatchBuiltin` |
| GraalWasm vs MuseInterp | Stress harness deltas = 0 (`graal/README.md` legs) |
| Sentinel / NaN encoding | Explicit tests for omitted-qty / empty windows |

If an optimization cannot preserve these, it does not ship behind a default-on flag.

---

## 23. Copy-paste snippets

### 23.1 Hot NMA walk skeleton

```haxe
static function walk(n:NmaNode, f:NmaNode->Void):Void {
	f(n);
	var i = 0;
	var c = n.childCount();
	while (i < c) {
		walk(n.childAt(i), f);
		i++;
	}
}
```

### 23.2 Unboxed min over a RingBuffer

```haxe
static function windowMin(w:RingBuffer<Float>):Float {
	var m = Math.POSITIVE_INFINITY;
	var i = 0;
	while (i < w.length) {
		var v = w.at(i);
		if (v < m) m = v;
		i++;
	}
	return m;
}
```

### 23.3 Safe optional bool from Dynamic args

```haxe
static function boolArg(args:Array<Dynamic>, i:Int, def:Bool):Bool {
	if (i >= args.length || args[i] == null) return def;
	var v:Dynamic = args[i];
	if (Std.isOfType(v, Bool)) return (v : Bool);
	if (Std.isOfType(v, Float) || Std.isOfType(v, Int)) return (v : Float) != 0.0;
	return def;
}
```

### 23.4 Shared Engine construction (host)

```haxe
var engine = Engine.newBuilder(GraalWasmHost.strArr(["wasm"]))
	.allowExperimentalOptions(true)
	.build();
// per thread:
var host = new GraalWasmHost(engine);
```

---

## 24. External references (canonical URLs)

| Topic | URL |
|---|---|
| GraalVM embed / Engine caching | https://www.graalvm.org/latest/reference-manual/embed-languages/ |
| Truffle monomorphization | https://www.graalvm.org/jdk25/graalvm-as-a-platform/language-implementation-framework/splitting/Monomorphization/ |
| Reporting polymorphism | https://www.graalvm.org/latest/graalvm-as-a-platform/language-implementation-framework/splitting/ReportingPolymorphism/ |
| Truffle DSL guidelines | https://www.graalvm.org/latest/graalvm-as-a-platform/language-implementation-framework/DSLGuidelines/ |
| Haxe `@:generic` | https://haxe.org/manual/type-system-generic.html |
| Haxe `Vector` | https://haxe.org/manual/std-vector.html |
| V8 hidden classes & ICs | https://chromium.googlesource.com/v8/v8/+/main/docs/runtime/hidden-classes-and-ics.md |
| V8 fast properties | https://v8.dev/blog/fast-properties |

---

## 25. Boxed map keys — `Map<Int,V>` is a `HashMap<Integer,V>`

Verified via `std/jvm/_std/haxe/ds/IntMap.hx`: on the JVM target `Map<Int,V>` is a thin wrapper
over `java.util.HashMap<Integer,V>`, so **every `set`/`get`/`exists` boxes the key** through
`java.lang.Integer`. Same trap as §3.1, one level up: you can have perfectly unboxed `double[]`
columns and still bleed allocation on the index bookkeeping around them.

For the **small, short-lived** int→int mappings this codebase actually builds (param remaps bounded
by a genome's param count — typically well under a few dozen), a linear scan over two parallel
`Array<Int>`s is allocation-free and, at that size, no slower than a hash lookup that has to box
first. Reference implementation: `Variation.ParamMapping` (`evo/Variation.hx`), used by
`remapOffsets`/`compactParams`, which run on **every** mutation/crossover child.

```haxe
class ParamMapping {           // beats Map<Int,Int> for n < ~dozens
  var keys:Array<Int> = [];
  var values:Array<Int> = [];
  public function set(k:Int, v:Int):Void { keys.push(k); values.push(v); }
  public function get(k:Int):Int {        // folds the exists()?get():k idiom into one call
    for (i in 0...keys.length) if (keys[i] == k) return values[i];
    return k;
  }
}
```

**Rule:** `Map<Int,V>` in a per-child or per-bar path is a code smell. Either parallel arrays (small,
scan-friendly) or a dense `haxe.ds.Vector<V>` indexed directly (when keys are a compact range).
`Map<String,V>` does *not* have this problem (no boxing — but see §26 for the key-*construction* cost).

---

## 26. Identity keys are not free — memoize the key, not just the value

`NmaCanonical.structuralKey` is `Sha1.encode(haxe.Serializer.run(...))` over a recursively-built
nested `Dynamic` array. That is **enormously** more expensive than the column arithmetic it guards:
it allocates a whole tree of arrays, serializes it to a string, then hashes it.

This is fine — *because it is memoized on the node* (`NmaNode.structuralKey`, populated lazily,
cleared by `invalidate()`):

```haxe
public static function seriesStructuralKey(n:NmaSeries):String {
  if (n.structuralKey != null) return n.structuralKey;   // ← the load-bearing line
  n.structuralKey = Sha1.encode(haxe.Serializer.run(keySeries(n))).substr(0, 16);
  return n.structuralKey;
}
```

**Two standing rules follow:**

1. **Never call a structural-key builder in a loop over bars.** Keys are per-*node*, computed once
   per node lifetime; columns are per-bar. Mixing those cadences is how an O(nodes) cost becomes
   O(nodes × bars).
2. **Any structural edit must `invalidate()` the node and its ancestors** (see `NmaDirtySpine`).
   A stale `structuralKey` after surgery is worse than a slow one: it silently aliases two different
   subtrees onto one pop-memo entry, which is a wrong-results bug, not a perf bug.

**Closure allocation at the memo seam.** The pop-memo call sites pass the key builder as a lambda so
it stays lazy when the memo is disabled:

```haxe
var shared = popLookup(ctx, () -> NmaCanonical.seriesStructuralKey(node));
```

`popLookup`/`popStore` are `inline`, so Haxe can flatten the lambda and the closure allocation
disappears — **but only while they stay `inline` and the lambda stays a direct call.** If you
de-inline those helpers, or capture more state, you reintroduce one closure allocation per node per
eval. If you touch that seam, re-run a JIT audit (§9) and check allocation counts, don't assume.

---

## 27. ⚠️ Process-global mutable statics vs. the evo worker pool

§21 covers not sharing mutable NMA *graphs* across workers. This section covers the sharper,
easier-to-miss hazard: **process-global `static var` caches, which are shared by construction.**

**The exposure is real and currently unguarded.** `CorpusEvoRun` creates a genuine worker pool
(`for (_ in 0...threads) Thread.create(...)`, the `fbJobQueue` fallback pool), and each worker calls
`Fitness.evaluate`. Under `--nma` / `--exec-profile`, `Fitness.preferNma = true` routes that straight
into `NmaFitness` → `NmaEpoch.of(...)`. No flag forces `threads = 1` when NMA is on. The
process-global mutable state reachable from those threads today:

| Static | Module | Hazard |
|---|---|---|
| `registry:Map<String,Int>` + `nextId:Int` | `NmaEpoch` | concurrent `set` on a `java.util.HashMap`; **`nextId++` is a non-atomic read-modify-write** |
| `sindColumns:Map<String,GrowableVec<Float>>` + `sindTapeKey` | `NmaFitness` | concurrent `get`/`set`; two-field invariant (`key`, `map`) updated non-atomically |
| `nmaPopMemo:Map<String,GrowableVec<Float>>`, `nmaPopMemoHits` | `Fitness` | concurrent `set`; lost counter increments |
| `sumByKey`/`nByKey`/`totalN` | `NmaCreditBank` | concurrent `set`; lost credit updates |
| `fnCache` | `Fitness` | concurrent `set` (pre-existing, same class of exposure) |

Two distinct failure modes, and the second is the dangerous one:

- **`java.util.HashMap` is not thread-safe.** Concurrent mutation during a resize can corrupt the
  table (historically, spin forever on a lookup). Loud, but at least obvious.
- **`nextId++` losing a race hands two *different* tape/param signatures the same epoch id.** A node
  memoized under tape A then reads as *valid* for tape B — `node.evalEpoch == ctx.epoch.id` passes,
  and it serves the wrong column. **Silent wrong numbers.** This is precisely the stale-cache class
  spec §7 exists to prevent, re-entering through the back door.

> **Note on the existing parity probe.** The `fbJobQueue` comment cites a probe confirming
> `Fitness.evaluate` is byte-identical under concurrent access — but that probe predates NMA and was
> reasoning about *harness-local* interp state. It does **not** cover these new
> process-global statics. Don't cite it as coverage for the NMA path.

**What to do (cheapest first):**

1. **Short term — make it explicit.** If `Fitness.preferNma` and `threads > 1`, either force
   `threads = 1` for the fallback pool or refuse with a clear message. A loud constraint beats a
   silent race.
2. **Correct fix — kill the shared mutability.** Epoch interning and the column caches want to be
   *either* per-worker (thread-local, losing only cross-thread sharing) *or* genuinely concurrent
   (`java.util.concurrent.ConcurrentHashMap` + `AtomicInteger` for `nextId`, via externs). Per-worker
   is simpler and matches §21's ownership discipline.
3. **Prove it either way.** Same shape as PLAN_EVO_SPEED's P3 probe: N genomes × M threads × K reps
   under `--nma`, assert every result identical to the serial run. Ship nothing default-on until
   that's green.

**Standing rule:** a new `static var` holding a `Map` or a counter in `evo/` is a concurrency
decision, not a caching convenience. Document its thread contract at the declaration.

---

## 28. Semantic fidelity beats mathematical correctness

When a fast path shadows an existing execution path, it must reproduce that path's **actual
observable behavior** — including behavior that is arguably a bug. "More correct" is a divergence.

**The case that taught us this** (found by the `NmaFitness` A/B, not by reading code): `Expand`
renders `KArith("min"/"max", a, b)` as a two-argument call `min(a, b)`, but MuseScript's `min`/`max`
builtins are **single-argument reducers over an iterable**
(`vars.set("min", xs -> IterDriver.min(MuseIters.from(xs)))`, `TradeBuiltins`). The second rendered
operand is silently dropped, so `min(a, b)` reduces the one-element iterable `a` and yields **`a`**.

`NmaEval.arith` therefore returns the **first operand** for `min`/`max`. A `Math.min(x, y)` there —
the "obviously correct" implementation — makes every genome using those ops diverge from production.

```haxe
// PARITY QUIRK: min/max are single-arg reducers; Expand's 2-arg render drops operand b.
// Interp and JS backend both do this, so NMA must too. Flagged, not silently "fixed" here —
// changing Expand would alter live production behavior and invalidate cached fitness.
case "min" | "max": x;
```

**Rule:** when the A/B disagrees, first ask *"what does production actually do?"* — not *"which is
mathematically right?"* Fix the quirk at its source (`Expand`) as a deliberate, separately-gated
behavior change with its own A/B, never as a silent side effect of adding a fast path.

---

## 29. Import hygiene addendum — secondary module types

Extends §7.5. Haxe's same-package auto-import brings each module's **primary** type into scope
(the one matching the filename) — **not** its secondary types. Every concrete node class except the
family bases is a secondary type (`NmaSPrice`/`NmaSInd` live in `NmaSeries.hx`, `NmaKArith` &c. in
`NmaScalar.hx`, `NmaBCross` &c. in `NmaBool.hx`). So any module doing kind-switch casts needs the
family modules imported **explicitly**, even from inside `musescript.evo.nma`:

```haxe
import musescript.evo.nma.NmaSeries;  // → NmaSPrice, NmaSInd
import musescript.evo.nma.NmaScalar;  // → NmaKConst, NmaKArith, …
import musescript.evo.nma.NmaBool;    // → NmaBCross, NmaBCmp, …
```

Symptom when missing: `Type not found : NmaBHole` plus a cascade of `Void should be …` errors on
every switch arm — the arms fail to type, so the switch's inferred type collapses. Cost us three
build cycles across `NmaBijection`, `NmaCanonical`, and `NmaEval`; it looks like a switch bug and is
actually an import bug.

Corollary: **do not `import` `NmaKind` unqualified** in a module that also builds evo enum trees —
importing an enum pulls its constructors into scope and `SPrice`/`KConst`/`BCross` collide. Fully
qualify (`musescript.evo.nma.NmaKind.BHole`) or alias per §7.5.

---

## 30. Measure the whole clock, and say what a timer excludes

§9 says measure. This section says measure *the thing you are claiming*, because we spent a long
time believing a number that was never the number.

`CorpusEvoRun`'s per-generation log line stamped `haxe.Timer.stamp() - tGen0` at a point BEFORE
speciation, novelty and `EvolutionEngine.step`. So it reported scoring time and everyone read it as
generation time. Measured at pop=1000 / threads=8 it printed ~700 ms against a real ~4766 ms
generation. Every wall-clock belief in the plan history — "22.9 s/gen", "sub-2 s/gen" — descends
from that line. It is now labelled `scoreMs`, and `--phase-profile` (`PhaseTimer`) reports the whole
clock with an explicit `unaccounted` residual.

**Rules:**

1. **A timing log states what it excludes**, in its label, not in a comment three files away.
2. **A phase that is not bracketed is a phase that is assumed.** Report the residual; an
   unexplained remainder is a finding, not rounding.
3. **No speed claim without a wall split.** "Kernel bars/s" and "gen/s" are different currencies and
   the exchange rate is the serial tail (§33).

The first `--phase-profile` run falsified two standing hypotheses in one shot — that fitness
evaluation dominated, and that the O(P²) diversity machinery would dominate at four digits. Both
were reasonable. Both were wrong. Measurement is cheaper than being reasonable.

---

## 31. Cost cadence — per-tape work belongs in per-tape state

§26 makes this point for identity keys. It generalizes, and the generalization is where the
expensive mistakes live: **ask what the work actually varies with, not where the code happens to
sit.**

`NmaFitness.prepare` ran per genome. Inside it, per *tape* work: five `Array<Float>` of length B
built from `bars` (boxed on JVM, §3.1), and a full FNV pass over the close column to derive the tape
key. At pop=1000 on a 1000-bar tape that is five million throwaway boxed doubles and a million
float-to-bits conversions per generation, to re-derive something that had not changed since the run
started. `NmaEvalContext.priceColumn` had the same shape one level down, rebuilding a `GrowableVec`
per context for a column the whole population shares.

The fix is a per-tape record (`NmaTapeState`) resolved by **reference equality on the bars array**
first — the orchestrator hands the same `Array<Bar>` to every genome in a generation — with the
content hash as the fallback that keeps a distinct-but-equal array correct rather than merely lucky.

**Checklist when adding anything to an eval path:** what does this vary with — bar, node, genome,
tape, run? Then put it in state with that lifetime. A cache one level too low is a leak; a
computation one level too high is the tax above.

---

## 32. A lock fixes a shared map, never a shared graph

Extends §27, which closed with a table of maps and counters. Those are now genuinely concurrent
(`EvoLock` on epoch interning, the credit bank, `NmaColumnCache` for the SInd/pop column shares, and
`fnCache`). The hazard §27's table does **not** cover is worse and was on by default.

`NmaDirtySpine.spliceAndRegister` builds a child pack that deliberately shares sibling node identity
with its parent — that sharing *is* the optimization — and hands the child the parent's
`NmaEvalContext` outright. Parent and child are two different structural keys, so the fallback pool
cheerfully dispatches them to two workers, which then race the same `NmaNode.lastSeries` /
`evalEpoch` fields. No amount of locking the registry helps: the shared object is the graph.

`CorpusEvoRun` now disables dirty-spine when the pool has more than one worker, loudly, and
`--threads 1` keeps it.

**Standing rule:** before guarding a shared cache, ask what its *values* are. Immutable-once-built
values (compiled programs, completed columns) need the map guarded and nothing else — the mutex
doubles as the publication barrier. Live mutable objects need an **owner**, and until one exists the
feature is single-threaded. Write which case you are in at the declaration.

---

## 33. The serial share is the ceiling

Report the non-parallel fraction next to any throughput number, because `--threads` cannot touch it.

Measured at pop=1000 / threads=8 / 320-bar tape / `--nma`: `EvolutionEngine.step` is **84.4%** of the
generation (4022 of 4766 ms) and is single-threaded end to end. Pooled evaluation is 14.8%. Keying,
speciation and novelty together are 0.7%. Driving evaluation to literally zero would buy 1.17×.

Attribution is about 52% of the whole generation (pop=256: 2602 ms/gen at `--attr-cross-prob 1.0`
versus 1253 ms/gen at `0`) and it buys real champion quality (2.64 vs 1.81 over six generations), so
it is a fitness decision rather than a free win. The sharper reading is the other half: with
attribution entirely off, `step` is *still* 62% of the wall. Plain variation is itself serial and
expensive, and no attribution policy touches that.

**Rule:** an optimization's ceiling is the share of the phase it lives in. Before optimizing, look
up the phase in a `--phase-profile` run and write down the best case. If the best case is under
1.2×, it is craft, not throughput — land it for the code's sake and say so.

---

## 34. A structural typedef is a dynamic-lookup box factory on the bar loop

§3.1 is about how you *store* floats. This is about how you *reach* them, and it hides one level
further down than the container choice: `musescript/harness/Bar.hx` is a `typedef`, so on the JVM
target it lowers to an anonymous class and `bar.close` compiles to
`haxe.jvm.Jvm.readField(Object, String)` → `Anon…._hx_getField(String)` — a string-keyed dynamic
lookup that returns a **boxed `java.lang.Double`**. There is no `getfield`, no unboxed `double`,
and nothing about the call site says so.

Invisible at feed cadence; ruinous on the bar loop. `NmaFitness.runPrepared` read `close` three or
four times a bar plus `open`/`high`/`low`/`index`, and `NmaPositionEval.featureAt` read `close` and
`index` again for every coupled node. JFR `jdk.ObjectAllocationSample` at `settings=profile`, on
`--pop 1000 --gens 20 --threads 8 --attr-bars 128` over a 320-bar tape:

| Site | `java.lang.Double` before | after |
|---|---|---|
| `NmaFitness.runPrepared` | 86.8 MB | not in profile |
| `NmaPositionEval.featureAt` | 21.5 MB | not in profile |
| all `Double` | 200.2 MB | 85.1 MB |

The fix is §31's cadence argument, not a `Bar` redesign — `Bar` is load-bearing across the
interpreter, the feeds, the compiled/WASM backends and hundreds of tests, and converting it to a
class is a separate change. Those five scalars are a pure function of the tape, so
`NmaBarColumns` derives them ONCE per tape into `haxe.ds.Vector` (real `double[]` / `int[]`),
`NmaFitness.tapeStateFor` builds them in the pass it already makes over `bars`, and the sim loop
indexes columns. `NmaPositionEval.boolAt`/`scalarAt`/`featureAt` take `barClose:Float,
barIndex:Int` instead of a `Bar` — a `Bar` parameter on a per-bar signature is the same trap one
frame up.

Two things that make it safe rather than merely fast:

1. **The columns carry the `Array<Bar>` they came from.** A retained context can legitimately be
   evaluated against a different tape with the same close-derived signature
   (`Fitness.evaluateNma`'s dirty-spine hit), and the old code read that tape's `open`/`index`
   directly. The reference guard re-derives instead of silently scoring tape B with tape A's bars.
2. **`bar.index` is not the loop counter.** `OrderSim` stamps fills with it and `bars_in_trade()`
   subtracts it, so it gets its own `Vector<Int>`, and `TestNmaBarColumns` numbers its tapes
   `i * 2` specifically so confusing the two changes the trades.

Same run, same shape, one level out: `OrderSim.equity` started at the `GrowableVec` default
capacity of 8 and doubled its way to the tape length, which JFR attributed as **71.1 MB of
`double[]` under `OrderSim.mark`** — six throwaway arrays and six `arraycopy`s per sim, and the
NMA path builds a sim per evaluation *and* per attribution column swap. `reserveEquity(n)` before
the loop; `[D` allocation for the run fell 129.7 MB → 46.4 MB.

**Rule:** on a per-bar signature, prefer scalars to records, and never let a structural typedef's
field access be the thing inside the loop. If a hot loop reads `x.field` where `x` is a typedef,
that is an allocation site until proven otherwise.

«τὸ ὄνομα βαρύ, ὁ ἀριθμὸς κοῦφος· λῦε τὸ ὄνομα.»

---

## 35. The V8 tier ladder — what "warm" actually means on Node/Electron

§6 said "shapes and ICs are everything" and §1.3 said warmup is part of the contract. This section
makes the V8 side of that as concrete as the JVM side, because the V8 pipeline gained a mid-tier
(**Maglev**) that changes what a microbench is measuring. The `--nma` stack now has a real V8 twin —
`NmaNodeBench` (`musescript/evo/NmaNodeBench.hx`, built by `build-nma-node-bench.hxml`, `-D node
-D js_es=6 -lib hxnodejs`) — so these are testable claims on this repo, not folklore.

### 35.1 Four tiers, four different things a stopwatch can catch

```
Ignition (bytecode interpreter)   ← cold; collects type feedback into feedback vectors
   ↓  ~8 calls / a loop backedge
Sparkplug (baseline non-optimizing compiler)  ← near-linear machine code, no speculation
   ↓  warmer
Maglev (mid-tier optimizing SSA JIT)  ← cheap speculation, fast to produce; newer, on by default in modern V8
   ↓  hot
TurboFan (top-tier optimizing JIT)  ← full escape analysis, inlining, the steady state you claim to measure
```

Consequences for every V8 bench in this codebase:

1. **A short loop times Sparkplug/Maglev, not TurboFan.** `NmaNodeBench`'s `--warm` pass (default 1
   full-population eval before the timed gens) is the minimum, not the target. For a steady-state
   claim, warm the *same call shapes* for enough iterations that `%GetOptimizationStatus` (see §38)
   reports TurboFan on `NmaEval.evalBool`/`evalScalar` and `OrderSim` methods. One warm gen over
   pop=256 is ~a few thousand node evals — enough for Maglev, borderline for TurboFan on the rarer
   arms.
2. **A deopt drops you back down the ladder, silently.** A single unexpected shape at a hot IC can
   kick a TurboFan function back to Sparkplug and re-collect feedback. The wall-clock symptom is a
   bench that is fast then slow then fast; the tool is `--trace-deopt` (§38), the fix is §6.1 shape
   stability.
3. **The tiers have different inlining budgets.** Code that "got faster" after a refactor may just
   have dropped under Maglev's smaller inlining threshold; confirm the win survives to TurboFan.

### 35.2 Node ≠ Electron ≠ your dev V8 — pin the version you reason about

Node bundles one V8; Electron bundles *its own*, tied to the Chromium it ships, which is usually a
**different** V8 than the Node you build with. Flag names (`--max-semi-space-size`), `%`-natives, and
even which tiers exist drift across versions. Rules:

- State the Node/Electron version next to any V8 measurement, the same way §5.2 pins the GraalVM
  version for polyglot. "Fast on Node 22" is not "fast in the shipped Electron app."
- The desktop app's evo/eval runs on **Electron's** V8. Bench there too (a `utilityProcess` or
  `worker_threads` entry running `NmaNodeBench`'s hot stack) before claiming a desktop number;
  `build-nma-node-bench.hxml` targets plain Node and is the *floor*, not the shipped ceiling.
- `-D js_es=6` (the bench's setting) fixes the emit level; it does not fix the runtime V8. Keep them
  named separately in any report.

«κισσὸς μὲν εἷς, ἀμπέλων δὲ πολλαί· γίγνωσκε τὴν σὴν κληματίδα.»

---

## 36. Smi vs HeapNumber, and PACKED vs HOLEY — the V8 twin of §3's boxing war

§3 fought `java.lang.Double` boxing on the JVM. V8 has the exact same war with two different fronts,
and the containers already picked the right side (`RingBuffer`/`GrowableVec`/`FloatSeries` all use
`js.lib.Float64Array` under `#if js`). Author new hot JS-target code to keep both fronts clean.

### 36.1 Smi vs HeapNumber

V8 tags a small integer (**Smi** — 31-bit on 64-bit builds) directly inside the pointer word: no heap
cell, no allocation. Any number that is fractional, or outside Smi range, becomes a **HeapNumber** —
a boxed `double` on the heap, the V8 analogue of `java.lang.Double`.

| Value on a hot JS path | V8 representation | Cost |
|---|---|---|
| `bar.index`, loop counters, param **indices** (`KParam.idx`), child counts | Smi | free, in-pointer |
| prices, columns, sharpe, `0.0`/`1.0` bool cells | HeapNumber (unless in a typed array) | heap cell per value |

This is why the `0.0`/`1.0` bool columns and every price/indicator column live in `Float64Array`,
not `Array<Float>`: a `Float64Array` slot **is** a raw IEEE-754 double in a backing store, so reading
and writing it never mints a HeapNumber. A plain `Array` of the same doubles is a `PACKED_DOUBLE`
array at best (see below) and boxes on the way out to any non-array-typed consumer.

Corollary: keep genuinely-integer hot fields as `Int` in Haxe (they stay Smi), and don't accidentally
turn a Smi into a HeapNumber by doing float math on it (`idx * 1.0`, `idx / 1`) before an index use.

### 36.2 Elements kinds — don't put a hole in a fast array

Even a plain `Array` has a V8 *elements kind* lattice, and it only ever transitions **downhill**:

```
PACKED_SMI_ELEMENTS  →  PACKED_DOUBLE_ELEMENTS  →  PACKED_ELEMENTS (tagged/boxed)
        ↓                        ↓                          ↓
HOLEY_SMI_ELEMENTS   →  HOLEY_DOUBLE_ELEMENTS   →  HOLEY_ELEMENTS
```

You cannot go back up. One hole (`a[5]=x` when length is 3; `new Array(n)` then sparse fill; `delete`)
or one boxed element (a `null`, an object) permanently demotes the whole array's fast path. Rules that
matter for the NMA/evo JS emit:

1. **Pre-size and fill densely, front to back.** `NmaNodeBench`'s `fitness.resize(popG.length)` then
   `fitness[i] = …` in order is the correct shape — no holes, stays PACKED.
2. **Never `arr[i] = null` as a placeholder** on a numeric hot array (that is exactly what
   `GrowableGenericImpl.setAt` does with its `push(null)` fill — fine there because it is the *generic*
   fallback for non-Float T, never the Float column; do not copy that pattern into a Float path).
3. **Don't mix kinds in one array.** A column is all doubles or it is not a column.
4. For anything that also touches WASM memory or is read every bar, **use the typed-array view**
   (already the container default) and skip the elements-kind lattice entirely.

«μῆλα χρυσᾶ μὴ κλέπτε ἐκ τῆς σειρᾶς· ἓν κενὸν πάντα λύει.»

---

## 37. Node/Electron process & concurrency model — the V8 answer to §27/§32

§21/§27/§32 are about the JVM worker pool sharing mutable NMA graphs and process-global statics. The
V8 side of parallel evo has a **different** hazard profile, and mostly a safer one — but only if you
use the right primitive.

### 37.1 Workers don't share the heap — which removes §27's whole class of bug

`worker_threads` (Node) / `utilityProcess` (Electron) each get their **own V8 isolate and heap**.
There is no shared mutable `static var` across JS workers by construction: the `Fitness.nmaPopMemo` /
`NmaEpoch.registry` / `NmaCreditBank` statics that §27 had to lock on the JVM are simply **not
shared** between JS workers. The silent-wrong-numbers race (`nextId++` handing two tapes one epoch id)
**cannot happen across JS workers**, because each worker has its own `nextId`.

**Landed for the score barrier:** `NmaNodeEvalPool` (`--threads N` on `NmaNodeBench`) spins persistent
workers, ships the tape once via `workerData`, and keeps a **resident genome store** keyed by dense
int ids (sticky `id % workers` ownership). JSON wire runs only for first-seen structural keys and
rides inline on the score message (no separate put RTT); score jobs send id lists through a
`SharedArrayBuffer` `Int32Array`. Haxe enums still cannot structured-clone. Structural-key dedup
mirrors CorpusEvoRun's clone collapse. `EvolutionEngine.step` child production stays serial on the
main isolate (§33) — do **not** arm `AttrPool` with `workers>1` on Node or Phase B silently switches
onto `forkForSlot` / `VARIATION_PARALLEL` streams with no real parallelism (champion drift).
Dirty-spine is refused when `threads > 1`. `popMemoHits` is partition-dependent across isolates —
not bit-stable under `--threads`. Champions / `nmaOk` bit-match across thread counts when AttrPool
stays at `workers=1`.

Measured (pop=1000 / smoke_spy_320 / warm=1 / gens=6, after resident-id wire):

| threads | cloneProb | mean wallMs | mean scoreMs | mean stepMs | gen/s |
|---|---|---|---|---|---|
| 1 | 0 | ~393 | ~106 | ~288 | ~2.5 |
| 4 | 0 | ~386 | ~83 | ~304 | ~2.6 |
| 8 | 0 | ~401 | ~93 | ~308 | ~2.5 |
| 4 | 0.4 | ~293 | ~72 | ~221 | ~3.4 |
| 4 | 0.5 + attrCross 0.25 | ~205 | ~71 | ~135 | ~4.9 |

JVM floor remains ~48 ms/gen at 4 threads. Without `--clone-prob`, wall is still Amdahl-bound by
serial `step` (~75–80%); killing the ~30 ms full-pop JSON floor buys scoreMs headroom on cache-hot
gens (`put n=0`) but not a ≥1.3× wall win alone. `--clone-prob` is the measured step lever on Node.

The cost moved, it did not vanish:

- **Crossing a worker boundary is a copy.** `postMessage` structured-clones its payload (deep copy);
  an `Array<Bar>` tape or a genome tree sent per job is a per-job serialization tax — the V8 analogue
  of §4.4's "materialize once at the seam." Send the tape **once** at worker spinup; resident ids
  make re-scores of elites/clones free; fresh children still pay JSON once per structural key.
- **Per-worker warmup is per-isolate.** Each worker climbs the §35 tier ladder independently. A pool
  of 8 short-lived workers each pays cold Ignition; a pool of 8 **persistent** workers (the JS twin of
  §5.1 "reuse the StrategyInstance") amortizes it. Spin the pool up once per run, feed it jobs.

### 37.2 When you *do* want shared numeric state: SharedArrayBuffer + Atomics

The one case where JS workers share memory is a `SharedArrayBuffer` (backing a `Float64Array` /
`Int32Array` view) coordinated with `Atomics`. This is the V8 mechanism for a genuine shared column
cache or a shared credit bank — and it re-imports §27/§32's discipline exactly:

- `Atomics.add`/`compareExchange` for a shared counter (the `nextId++` fix, done right);
- an `Atomics`-guarded publish for a completed immutable column (the mutex-as-publication-barrier of
  §32); a *live mutable* graph still has no owner and still does not belong in shared memory.
- Note Electron requires the cross-origin isolation headers (`COOP`/`COEP`) for `SharedArrayBuffer`
  in a renderer; a `utilityProcess`/`worker_threads` context is the cleaner home for it.

Standing rule, mirroring §27's: **a `SharedArrayBuffer` view is a concurrency decision, not a buffer
convenience.** Document its access contract at the allocation site. Default evo parallelism on V8
should be message-passed persistent workers (37.1); reach for shared memory only when the copy tax is
measured to dominate.

### 37.3 Electron-specific: keep evo off the UI threads

- **Never run a fitness pass on the renderer's main thread or the browser process main thread** — it
  blocks paint and IPC. Evo/eval belongs in `worker_threads` or a `utilityProcess`. Strategy Studio's
  interactive eval is the exception (one-shot, user-initiated, small tape) and even that should yield.
- **Packaging changes `fs`.** `NmaNodeBench.loadBars` reads a CSV off disk; inside an `asar` archive
  the path resolution differs, and a shipped app should hand the tape to the worker as data (37.1),
  not assume a readable file path. Don't let a bench's `sys.io.File.getContent` shape leak into the
  packaged eval path.
- **GC pressure is the app's frame budget.** Columnar eval mints short-lived `Float64Array` columns by
  the thousand; on the JVM that is escape-analysis territory (§20), on V8 it is nursery (young-gen)
  churn. If a `--cpu-prof` shows scavenge GC hot, `--max-semi-space-size` (a larger nursery) is the
  first knob — but §9.4 applies: profile the whale before turning knobs, and the whale on the JS side
  is likely the same serial `EvolutionEngine.step` share as §33, not GC.

«τρεῖς θύραι· μία τῷ χορῷ, οὐχ ἡ τοῦ θεάτρου.»

---

## 38. V8 measurement & deopt tooling — the `jit_audit_run.sh` we still owe the JS side

§9 gives the JVM a real auditor (`scripts/jit_audit_run.sh` → deopt/inline summary). The JS side has
`NmaNodeBench`'s counters (`nmaOk`/`nmaFall`/`popMemoHits`, `scoreMs` vs `wallMs`) but **no deopt
audit script yet** — that is an owed tool, not an existing one (§ Document maintenance).

### 38.1 Node flags that make V8 tiering observable

| Flag | Shows | Use when |
|---|---|---|
| `--trace-opt` | which functions TurboFan/Maglev optimized | confirm your hot fn actually tiered up |
| `--trace-deopt` | deopt site + bailout reason | the "fast then slow then fast" bench; shape bugs |
| `--trace-ic` | IC state transitions (mono→poly→mega) per site | chasing a megamorphic property/call site (§6.1) |
| `--allow-natives-syntax` | enables `%`-intrinsics below | targeted A/B in a throwaway harness |
| `--prof` / `--cpu-prof` | sampling profiler / `.cpuprofile` for DevTools | find the JS whale (§9.4) |

With `--allow-natives-syntax`, a throwaway probe can assert tiering the way §9's audit asserts inlines:

```js
// probe only — never ship %-syntax in the emit
%PrepareFunctionForOptimization(f);
f(warmArgs); f(warmArgs);
%OptimizeFunctionOnNextCall(f);
f(warmArgs);
// 1 = optimized (TurboFan/Maglev). See V8's OptimizationStatus bitmask.
print(%GetOptimizationStatus(f));
```

### 38.2 Standing V8 measurement rules (mirror of §9.2/§30)

1. **Warm deliberately, then time** — §35.1. State the warm count. `NmaNodeBench --warm` is that knob.
2. **Same-seed A/B, bit-identical gen lines** for any zero-behavior-change phase (§22). The bench
   already prints per-gen `best`/`nmaOk`/`nmaFall`/`popMemoHits`; a shape/container refactor must not
   move `nmaOk`/`nmaFall`.
3. **Report `scoreMs` and `wallMs` separately** — the bench does; `scoreMs` is the fitness barrier,
   `wallMs` includes serial `step` (§33's ceiling is a V8 fact too, single-threaded here by design).
4. **Name the V8 version** (§35.2). A deopt reason is version-specific.

**Owed tool (do not pretend it exists):** a `scripts/v8_deopt_run` analogous to `jit_audit_run.sh` —
run `NmaNodeBench` under `--trace-deopt --trace-opt`, parse the log into a summary of top deopt
sites/reasons and any hot `musescript.*` function that never reached TurboFan. Until it lands, a manual
`node --trace-deopt build/js/nma-node-bench.js … 2>&1 | grep -i musescript` is the interim audit.

«ὁ μὲν αὐλὸς λέγει ταχύς, ὁ δὲ ῥυθμὸς κρίνει· μέτρει, μὴ πίστευε.»

---

## Document maintenance

Update this guide when any of the following lands:

- A concrete `NmaKernel` emitter (replace §2.4 aspirational text with the real ABI)
- The shared hyper-opt vector type (`SymbolSelector` TODO resolved)
- A measured LastTier / Engine-option recommendation that beats the default
- A new verified boxing footgun (add to §10 with the decompile/audit evidence). Latest: §34,
  structural-typedef field reads on the bar loop (`scripts/jfr_alloc.ps1` reproduces the numbers)
- A dual-rep change that alters bijection or epoch semantics
- **§27's map/counter hazards are CLOSED** (`EvoLock` guards epoch interning, the credit bank, the
  column caches and `fnCache`); the graph-ownership hazard is documented in §32 and handled by
  disabling dirty-spine above one worker. **Determinism probe LANDED (Node + JVM):**
  `NmaNodeBench --det-probe` / `scripts/nma_thread_det_probe.ps1` and
  `CorpusEvoRun --det-probe` / `scripts/nma_jvm_thread_det_probe.ps1` — N×M×K identical to serial
  on the real Node worker_threads pool and the CorpusEvoRun JS-fallback Deque pool under `--nma`
- A parallel or cheaper `EvolutionEngine.step` — §33's numbers are the current ceiling and should be
  re-measured, not edited, when that lands
- **§35–§38 (V8 / Node / Electron):** `NmaNodeEvalPool` / `--threads` score fan-out + **resident
  genome ids** (sticky ownership, inline JSON put on score) landed on `NmaNodeBench` (§37.1).
  `--clone-prob` is wired on the Node bench as the measured step lever. Still owed: (a) a
  `scripts/v8_deopt_run` twin of `jit_audit_run.sh` (§38.2); (b) a first
  `%GetOptimizationStatus`-verified TurboFan-warm number on `NmaEval`/`OrderSim` under Node;
  (c) the same measured on the shipped **Electron** V8, not just plain Node (§35.2); (d) a
  binary/SAB genome codec to replace remaining JSON puts for high-churn children (resident ids
  already zero the re-score tax). Replace aspirational framing with measured numbers as they land.

PR description should cite the section number you changed.

**House style:** every `/** … */` in `evo/nma/` ends with a short cultic Greek verse
(Dionysian / Orphic / Sibylline register), marked «…».

---

*Code-cooter out. Keep the kind-switch holy; keep the doubles unboxed; keep the Engine
warm; keep the Maps monomorphic. Everything else is commentary.*

«εὑρήκαμεν, συγκάθομεν· Βάκχος ἡγεῖται.»
