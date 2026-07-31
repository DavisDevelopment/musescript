# SPEC — A stack-bytecode IR + VM (and the GraalVM/Truffle force-multiplier)

**Status:** Design spec, 2026-07-31. Replaces the tree-walking `MuseInterp` on the hot path with a
compile-once **stack-bytecode IR** run by a tight VM. On GraalVM this is not "a bit faster" — a
Truffle-hosted bytecode interpreter is **partially evaluated to native code specialized per
strategy**, which can subsume the hand-emitted WASM tier for the evo oracle *and* open in-process
Polyglot interop with the Python ML stack.

**The two problems it kills at once:**
1. `MuseInterp` is a **tree-walker** — it re-dispatches on every AST node, every bar. It is both the
   steppable/debug tier *and* the slow serial path the attribution oracle leans on
   (`PLAN_EVO_SPEED.md`: `evalFn` re-parses + runs the full 8-pass compile + a tree-walk backtest
   **per ablation, serial, zero caching**).
2. There is no cacheable compiled artifact for oracle memoization. **The bytecode is that artifact.**

---

## 1. The shared stack IR (one compiler, many consumers)

Add one pass, `MuseBytecodeCompiler` (AST → bytecode), placed **after** the existing optimizer
(post `ConstFold`/`CommonSubexprElim`/`CallsiteIds`, so it lowers the *optimized* AST and callsite
ids are already assigned). It emits:

- a flat `Int` (or typed) **instruction array** + a **constant pool**,
- a **callsite-slot map** (indicator/cross state slots, keyed by the `CallsiteIds` ids — §5),
- a **local-slot layout**, and
- a **source-span table** (pc → span) for stepping.

The IR is a **stack machine** — which is the deep "stack language" synergy: the WASM backend
(`StrategyWasmEmitter`/`WatAssembler`) *already* lowers to a stack machine (WAT is stack-based). So
the bytecode IR and the WASM lowering are siblings; ideally the bytecode IR becomes the **retargetable
stack IR both consume**, and the existing JS/WASM emitters lower *from* it instead of from the AST.
One IR → { portable VM, WASM, JS }.

Consumers:
- **Tier A — portable Haxe stack VM** (`MuseVM`): runs everywhere the Haxe build runs (browser,
  desktop, node). Replaces the tree-walk interp as the default fast interpreter.
- **Tier B — GraalVM/Truffle bytecode interpreter** (server/oracle): §3, the force-multiplier.
- (existing) **WASM/JS emitters**: kept for their niches (browser WASM subset, JS tier), now
  ideally fed by the same IR.

## 2. Instruction set (grounded in `MuseInterp.evalExpr`/`execStmt`)

- **Values/locals:** `CONST k`, `LOAD_LOCAL i`, `STORE_LOCAL i`, `LOAD_IDENT g`.
- **Arithmetic/logic (all via `DetMath` for parity):** `ADD SUB MUL DIV MOD NEG`, cmp
  `LT LE GT GE EQ NE`, `NOT`; `AND`/`OR` via short-circuit jumps.
- **Control:** `JUMP`, `JZ`, `JNZ` (covers `EIf`/`EWhile`/`ETernary`/`EFor`).
- **Calls/closures:** `CALL n`, `CALL_METHOD name n` (class dispatch by `__class`), `CALL_BUILTIN
  id n`, `RET`, `MAKE_CLOSURE k` (captures upvalues → `FnClosure`).
- **Domain-specific (the parity crux):**
  - `BAR_FIELD name` (`EBarField`), `LOOKBACK` (`ELookback` — series[n], indexed into a callsite
    ring buffer).
  - `SERIES id n` — a stateful indicator call (`EMeta("__scr", [id], call)`); the id selects a
    **fixed VM series slot** (pre-allocated `IndicatorInstance`/`SeriesBuffer`), so per-callsite
    state is byte-stable — this is exactly how the interp stays deterministic today.
  - `CROSS id n` — crossover/cross state (`EMeta("__cs", …)`), same callsite-keyed slot mechanism.
  - `ORDER kind n` (`Order` stmt) → `OrderSim`.
  - `NEW_OBJ`/`NEW_ARR`/`GET_FIELD`/`SET_FIELD`/`GET_INDEX`; `MATCH …` (lower `EMatch` to a jump
    table + binding stores via the existing `PatternMatcher` semantics).
- **Generators/iterators (`EYield`/`EYieldStar` + the `MuseIter` library):** hard in a plain stack
  VM (resumable frames). **Tier A P0 defers these to an interp fallback** (the evo hot path is
  `onBar`/`when`/`order` — the fast subset, mirroring the WASM "on_bar subset" precedent). **Tier B
  gets them for free** via Truffle Bytecode DSL **continuations** (§3).

## 3. Tier B — the GraalVM/Truffle force-multiplier (the point of this spec)

The evo oracle already runs on GraalVM (GraalWasm workers, `build/graal/*`). A Truffle-hosted
interpreter turns that from "a place we host WASM" into "a place Graal writes us a compiler."

**Partial evaluation (Futamura).** Write the bytecode interpreter with the Truffle **Bytecode DSL**
(GraalVM's framework for PE-friendly bytecode interpreters). Graal's partial evaluator specializes
the interpreter *to the specific strategy's bytecode* and JITs the result to **native code** — the
per-bar dispatch loop unrolls, the strategy becomes near-straight-line machine code. This is how
GraalJS/TruffleRuby reach near-native speed; you get a compiler by writing an interpreter.

**Why it plausibly *subsumes* the WASM tier for the oracle:**
- No per-genome WASM emission + module instantiation cost (real overhead in the current path — you
  pay `WatAssembler` + instantiate per candidate). The Truffle interp compiles the *interpreter once*
  and PE-specializes cheaply per strategy; long evo runs amortize warmup beautifully (many gens).
- Far less backend code to maintain than the hand-rolled `StrategyWasmEmitter` + WAT runtime.
- The three hard parts fall out of the Bytecode DSL: **continuations** → generators/`MuseIter` work
  on Tier B; **instrumentation** → the stepping debugger works on bytecode; **boxing elimination /
  quickening** → the numeric hot path runs unboxed. These are the exact items I'd have hand-built.

**PE hygiene (what makes it actually compile well):** mark the bytecode array, constant pool,
callsite-slot layout, and local-slot layout `@CompilationFinal`; use
`CompilerAsserts.partialEvaluationConstant` on the opcode dispatch; `transferToInterpreterAndInvalidate`
on genuinely-rare paths (NaN/inf handling, dynamic fallback) so the hot path stays tight. Node
self-specialization (`@Specialization`) collapses the arithmetic-heavy indicator math to a
monomorphic numeric path.

**Polyglot (the second unlock).** On GraalVM, MuseScript values as Truffle interop objects mean the
Python ML stack (the Kestrel/ProbCloud fit bridge, torch/numpy) and JS become **in-process,
zero-copy** callees — no process boundary, no serialization. The current Haxe↔Python bridge crosses
a process; Polyglot collapses it into the VM. (Design only; gated behind the oracle tier.)

**Boundary honesty:** Truffle is Java-side (the Haxe→JVM pipeline doesn't emit Truffle nodes). Tier B
is a **Java/Kotlin component that consumes the Haxe-produced bytecode**, living beside the Haxe. It
is **GraalVM-only** — so it's the *server/oracle* tier; the browser/desktop keep Tier A (portable
Haxe VM) + the JS/WASM emitters. Clear tiering, no portability regression.

## 4. Determinism / parity (sacred — the honest gate)

The VM is a new execution tier; the parity contract (interp ↔ js ↔ wasm byte-identical) **must**
extend to it: interp ↔ Tier-A-VM ↔ Tier-B-Truffle, all byte-identical on the corpus.
- All arithmetic through `DetMath`; exact integer narrowing; identical NaN/inf/`-0.0` handling;
  callsite-slot state identical to the interp.
- Graal PE preserves semantics, and Graal respects IEEE-754 — but this is **verified, not assumed**:
  extend the `DetParityDump` golden-file harness to emit from the VM and the Truffle tier and diff
  against the interp. **A tier ships only when its golden file is byte-identical.** No exceptions —
  a fast tier that lies is worse than a slow one that doesn't.

## 5. Steppability
Tier A: the pc→span table drives `MuseDebugSession` (step by pc → source line; breakpoints = pc
predicates); the tree-walk interp remains the reference/fallback stepper. Tier B: Truffle
**instrumentation** gives stepping/breakpoints natively over the bytecode.

## 6. Oracle integration (the payoff, ties to the #1 speed pick)
Cache compiled bytecode by **structural hash** (extend `EvoCache`, currently fitness-only, to the
compiled program). A mutated child recompiles only on cache miss (P0: whole-program by structural
key; P1: incremental — recompile only the changed subtree's bytecode). The oracle runs the VM/Truffle
tier instead of re-parse + 8-pass-compile + tree-walk. Compile-once + PE-to-native is the compounding
win named in `PLAN_EVO_SPEED.md`.

## 7. Performance targets
- Tier A: **3–10×** the tree-walk interp on the backtest hot path (classic tree-walk→bytecode range).
- Tier B: approach the emitted-WASM tier while removing per-genome emit/instantiate overhead; the
  real target is **warm s/gen** on the `CorpusEvoRun` baseline (the stale 22.9s/gen figure → measure).
- The gains concentrate in: unboxed numeric operand path, superinstructions (fuse `LOAD_LOCAL`+cmp),
  inline caches for method/field dispatch, and (Tier B) PE unrolling the per-bar loop.

## 8. Phasing
- **P0** — `MuseBytecodeCompiler` + Tier-A `MuseVM` for the **strategy `onBar`/`when`/`order`
  subset** (the evo hot path): consts, locals, `DetMath` arithmetic, cmp, short-circuit, bar fields,
  lookback, `SERIES`/`CROSS` callsite state, orders, if/ternary. Parity gate vs interp on the corpus.
  Wire the oracle to Tier A behind a flag.
- **P1** — numeric fast path (unboxed operand stack) + superinstructions + inline caches (the real
  speedup) + oracle bytecode cache (§6).
- **P2** — **Tier B: Truffle Bytecode DSL interpreter** on the Graal oracle; `@CompilationFinal` PE
  hygiene; parity golden-file. Measure vs the WASM tier; if it wins, make it the oracle default.
- **P3** — broaden Tier-A coverage (objects/arrays/classes/match) with interp fallback for the tail;
  generators via interp (Tier A) / continuations (Tier B).
- **P4** — Polyglot in-process Python/JS interop on Tier B (collapse the Kestrel/ProbCloud process
  bridge); retarget JS/WASM emitters to lower *from* the shared IR (§1).

## 9. Honest caveats
- Tier B is Java/Kotlin + Truffle, **GraalVM-only** — a real new component and dependency; it earns
  its place only on the server oracle, not the portable tiers.
- Graal PE has **warmup**; great for long evo runs (amortized), worse for one-shot short runs — so
  Tier B is for the oracle/batch, Tier A for interactive/browser.
- The parity gate is non-negotiable and is the gating risk: getting three tiers byte-identical
  (esp. float edge cases through PE) is the hard, careful work. Budget for it.

## 10. Open questions
- **Stack vs register VM** (spec: stack for P0 simplicity; register is faster but the Truffle
  Bytecode DSL + PE narrows the gap — revisit only if Tier A is the bottleneck and Tier B isn't chosen).
- **Whole-program vs incremental bytecode caching** (whole-program P0).
- **Does Tier B replace or complement the WASM tier?** Decide empirically at P2 on measured warm
  s/gen — the WASM tier stays for the browser regardless; the question is only the *server oracle*.
- **Shared-IR retargeting** (JS/WASM lower from the bytecode IR) — attractive unification, but sequence
  it after Tier A proves the IR; don't destabilize the audited WASM parity to get it.
