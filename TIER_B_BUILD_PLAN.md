# Tier B build plan — breaking the builtin ceiling

**Status:** scoping doc, 2026-07-31. Design/rationale in `SPEC_BYTECODE_VM.md` §3/§11; execution
checklist in `BYTECODE_VM_TODO.md`. This file is the concrete plan for the *speed* leap the P0–P1
Dynamic-stack VM cannot reach on its own.

## The finding that reframes Tier B

P1 measured the Dynamic VM at **~1.2× the interp on JVM** for real (indicator-heavy) genomes
(`VM_PERF_TRAIL.md`). The cause is structural: the VM compiles `sma(close,8)` to an **opaque
`CALL_BUILTIN`** (`Reflect.callMethod` into Haxe `TradeBuiltins`), *identical* to what the interp
does — so when the per-bar cost is dominated by the indicator call, the VM can only speed the
dispatch *around* it. Ceiling ~1.2×.

**The WASM tier already broke this ceiling** — and not with partial evaluation. `StrategyWasmEmitter`
**lowers the indicator math to WAT primitives** (ring-buffer sums, EMA recurrences) instead of calling
a builtin; it only falls back to interp for opaque-*returning* builtins (probcloud/graph queries — the
cold path). That inlined numeric body is *why* WASM is the pop-scoring fast tier.

**Consequence for sequencing:** the ceiling-breaker is **lowering indicators to primitive bytecode**,
and that lowering logic *already exists* in `StrategyWasmEmitter`. Do that FIRST (TB0) — it is
target-agnostic (helps the portable Haxe VM *and* the JVM), it may deliver most of the win on its own,
and it is the prerequisite that makes Tier B's partial evaluation actually pay (PE can only specialize
a numeric body it can *see*; it cannot inline an opaque `Reflect` call). **Measure after TB0 before
committing to the Truffle component** — TB0 might make Tier B unnecessary for anything but the last mile.

---

## TB0 — Lower indicators to primitive bytecode (target-agnostic, THE ceiling-breaker) ⭐

The real work, and the highest ROI. No Java, no Truffle — pure Haxe, helps every tier.

- **Add stateful primitive ops + a callsite ring-buffer slot** to the bytecode IR: `RING_PUSH slot`,
  `RING_SUM slot n`, `RING_AT slot k`, plus EMA/RMA recurrence ops (`EMA_STEP slot alpha`). Keyed by
  the `CallsiteIds` id exactly like `SERIES`/`CROSS` state today, so per-callsite state stays
  byte-stable (§ the parity crux the whole VM already respects).
- **Port `StrategyWasmEmitter`'s indicator lowering to bytecode**: reuse its exact recurrences
  (`emitValue`/`emitStmt` for `sma`/`ema`/`rsi`/`atr`/…) so the lowered bytecode is byte-identical to
  the WASM math (and therefore to the interp — the three already agree on the corpus). Indicators the
  WASM emitter can't lower (opaque-returning) stay `CALL_BUILTIN` → interp fallback, same boundary.
- **Compiler**: when a `CALL_BUILTIN name` is a lowerable indicator, emit its primitive-op body
  instead of the opaque call. Everything else unchanged.
- **Gate**: the existing `VmParityDump` corpus + evolved gates (83/83, 2430 @ diverged=0) must stay
  green — this is a big lowering change, so this is where the careful parity work lives.
- **Measure** (`vm_bench_trail.sh`): expect the JVM per-eval to move well past 1.2× (toward WASM) on
  indicator genomes, and the portable tier likewise. **This is the checkpoint that decides whether
  Tier B is even needed.** Record it.

## TB1 — GraalVM Truffle Bytecode-DSL scaffolding (only if TB0's ceiling still matters)

- Truffle runtime is already on the classpath (`truffle-api/runtime/compiler-25.1.3`, via GraalWasm).
  Add the **Bytecode DSL annotation processor** (`truffle-dsl-processor`) to a new Java/Kotlin module
  `tierb/` (Maven), separate from the Haxe jar. GraalVM-only (spec §9).
- Wire a `build-tierb.*` that compiles the Java module against the same GraalVM, and a classpath entry
  so `CorpusEvoRun` (Haxe-JVM) can call into it.

## TB2 — Bytecode bridge (Haxe `MuseChunk` → Java)

- The Haxe `MuseChunk` (`code:Array<Int>`, `consts:Array<Dynamic>`, `localNames`, and the new TB0
  ring-buffer slot map) is already a JVM object at runtime. Cross it to Java either by (a) a flat
  serialization (`int[] code`, `Object[] consts`) the Java side reads, or (b) direct field access to
  the Haxe-emitted class. Prefer (a) — a stable, dumb contract that survives Haxe codegen changes.
- Java side reconstructs a `MuseBytecodeRoot` from the int[]/Object[]; the harness (`OrderSim`, series
  ring buffers, `DetRng`) is passed as a `MuseContext` (§11.5).

## TB3 — The Bytecode-DSL interpreter (spec §11, made concrete on TB0's IR)

- `@GenerateBytecode(enableYield=true, enableTagInstrumentation=true)` root node — yields give
  generators, tag instrumentation gives the stepping debugger, both free (§11.1).
- **Numeric specialization** (§11.2): arithmetic/compare `@Specialization` to `double`; rare boxed/NaN
  path `transferToInterpreter`. Every numeric op routes through a **Java DetMath** that is
  byte-identical to `musescript/ew/mcmc/DetMath.hx` (IEEE-only `exp`/`log`) — the determinism
  obligation (§4/§11.6).
- **Callsite slots as PE constants** (§11.3): the `CallsiteIds` id is a bytecode immediate ⇒
  `partialEvaluationConstant`, so `slots[id]` folds to a constant address and — *because TB0 lowered
  the indicator to primitive ops* — the ring-buffer update **inlines into the strategy body**. This is
  the exact line where Tier B beats the Dynamic VM: the indicator math is now PE-specialized native
  code, not an opaque call.
- `@CompilationFinal` on the code array, const pool, slot layout, locals (§11 PE hygiene).

## TB4 — Parity gate (5th tier; non-negotiable)

- Extend `VmParityDump` / `DetParityDump` to emit raw-f64 trades+equity from the Tier-B tier and diff
  against the interp on the corpus + evolved genomes. **Tier B ships only when that diff is empty**
  (§4). Getting three→four→five tiers byte-identical through PE (float edge cases) is the gating risk;
  budget for it.

## TB5 — Measure vs WASM + the kill-criterion (spec §9)

- A/B warm s/gen on the canonical baseline (pop=80/gens=30/seed=42/NVDA), Tier B oracle vs WASM.
- **Kill-criterion:** Tier B becomes the oracle default only if it beats the WASM tier's warm s/gen by
  **≥1.5×** OR decisively removes the per-genome WAT-emit+instantiate residual. Else it stays a
  research branch and Tier A + WASM ship. **No promotion on faith.**

---

## Honest risks & the likely outcome

- **TB0 may be the whole win.** If lowering indicators to bytecode gets the Dynamic VM near WASM speed
  target-agnostically, Tier B's marginal value (the JVM oracle) is Amdahl-capped and may not clear its
  own kill-criterion. That would be a *good* outcome: the portable/on-device tiers get the speed
  without a GraalVM-only Java/Truffle component to maintain. **Sequence TB0, measure, then decide.**
- **Tier B is a second language + build** (Java/Truffle, GraalVM-only) carrying the hardest parity
  burden (float through PE). It earns its place only on the server oracle, and only past TB5.
- **The pop already uses WASM.** Tier B's real structural prize is removing the per-genome
  emit+instantiate overhead *and* deleting the hand-rolled WAT backend — a maintenance/throughput win,
  not just per-bar speed. Weigh that, not raw per-bar, at TB5.

## One-line recommendation

Build **TB0** (indicator→bytecode lowering, reusing `StrategyWasmEmitter`'s math) — it is the actual
ceiling-breaker, pure Haxe, helps every tier, and is the honest prerequisite. **Measure. Then** decide
whether the Truffle Tier B (TB1–TB5) earns its keep, using the numbers, not the spec's optimism.
