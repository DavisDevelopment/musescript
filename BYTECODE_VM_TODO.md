# Bytecode VM (Tier A) — Living Checklist

**Date:** 2026-07-31
**Spec:** `SPEC_BYTECODE_VM.md` (design + rationale live there; this file tracks execution only).
**State at creation:** P0 vertical slice exists in the working tree but is **uncommitted**
(`musescript/vm/` — `Op`, `MuseChunk`, `MuseVmOps`, `MuseBytecodeCompiler`, `MuseVm`;
`TestBytecodeVmParity`; `build-vm-tests.hxml`). Subset = no-indicator `onBar`/`when`/`order`,
~15 opcodes, out-of-subset ⇒ deterministic `VmUnsupported` fallback. Parity test green locally
(raw-f64-bit trades + equity, 6 programs) but **not in CI**, and only the spec has commits.

## Ground rules

- **Parity is the gate, speed is the payoff — in that order.** No opcode ships without the
  interp↔VM byte-identical gate covering it. A fast tier that lies is worse than a slow one that doesn't.
- **`AND`/`OR` are NOT short-circuit** (both operands always evaluate, matching interp + WASM).
  Any future "optimization" that reintroduces short-circuiting is a parity bug, full stop.
- **The fallback boundary must stay deterministic:** whole-program compile-or-throw. Never
  half-compile a program.
- **Honest denominator:** warm evo baseline is **~4.35 s/gen** (measured 2026-07-31; see spec §7),
  already cache-dominated. Tier A's win is on the **cache-miss / per-eval** path. Never quote the
  stale 22.9 s/gen.
- **Tier B (Truffle) is hypothesis, not plan-of-record.** ≥1.5× warm s/gen vs the WASM tier or it
  stays a research branch (spec §9).

---

## P0 — finish the vertical slice (ordered; do in this order)

- [x] **V0. Ship the slice.** Committed `musescript/vm/`, `TestBytecodeVmParity.hx`,
  `build-vm-tests.hxml` + spec status (commit `31026c3`).
- [x] **V1. CI gate.** Added a scoped runner `TestVmMain` + `build-vm-parity.hxml` +
  `pipeline-hardening.yml` step "Build + run bytecode VM parity gate". Scoped deliberately (not the
  whole TestMain suite, which the maintainers don't gate on). Green locally (19 asserts, exit 0).
- [x] **V2. Parity harness before opcode growth.** `musescript/vm/VmParityDump.hx` (reusable, pure)
  classifies each program identical/fallback/interpError/diverged over raw-f64 trades+equity bits.
  `TestVmParityCorpus` feeds it the REAL evo gen-0 corpus (`seedFromIndicators` over
  `RegistryPalette.compatibleNames()` + fib + fourier, as `CorpusEvoRun` seeds) + the subset programs.
  Invariant `diverged==0` now gates in CI. Current coverage: 83 progs → identical=3, fallback=80,
  diverged=0 — `fallback` shrinks as V3 lands, each newly-covered genome byte-checked for free.
- [x] **V3. Indicator subset — the real unlock. DONE.** `a5ee099` CROSS+CALL_BUILTIN, `78ed65c`
  LOOKBACK, `1b38afc` EField+`__scr` SERIES. **Corpus gate: identical 3 → 83, fallback 80 → 0,
  diverged=0** — the ENTIRE evo gen-0 corpus runs on the VM byte-identically to the interp. Full suite
  green (75,091 asserts). Ops added: `CALL_BUILTIN` (static series-name arg resolution + `MuseVmBuiltins`
  mirror of `installBuiltins` + scratch capability check), `CROSS` (`__cs` crossover/crossunder/rising/
  falling), `LOOKBACK` (bar-field/ident `series[n]`), `GET_FIELD` (`obj.field`), `SERIES` (`__scr`
  macd/bbands/stoch → scratch object). Still deferred (deterministic fallback): `ELookback` of an
  `ECall`/offset series (`withSeriesOffset` re-entrancy), user-`@indicator` `__cs`, method calls,
  objects/arrays/match/generators/loops. Design detail retained below.

  Original target: `LOOKBACK`, `SERIES id n`, `CROSS id n` mirroring
  interp semantics exactly: callsite-keyed slots via `CallsiteIds` ids, same
  `HarnessContext.seriesBuffers` / `IndicatorInstance.stateFor` / `TradeBuiltins.*CS` state.
  Until this lands, nearly every real evo genome misses the VM (V2 gate: 80/83 fallback).

  **Design notes (reverse-engineered 2026-07-31, ready to execute against the V2 gate):**
  - Seed genomes expand to e.g. `when crossover("close", sma("close", 8)): { long(1); }`. Series
    args render as **string literals** (`"close"`), NOT bar-field idents (`Expand.series` →
    `'"'+f+'"'`). So `sma`'s series arg arrives as `EConst(CString("close"))`.
  - **Plain builtin call** (`sma`/`ema`/~400 indicators): interp does `ECall(EIdent(name), args)` →
    `evalCallArgs` → for arg i, if `BuiltinSigs.wantsSeries(name,i)` pass `seriesNameOf(args[i])`
    (a NAME string) else `evalExpr(args[i])`; then `callValue(calleeValue(callee), argv)`. The
    builtin lives in `globals` (`TradeBuiltins.install`) and reads harness series columns.
    **`evalCallArgs` series-name resolution is STATIC per callsite** (depends on the arg AST, not
    runtime values) — so the compiler can decide at compile time: series-typed arg ⇒ emit
    `CONST "<name>"`; else emit the arg's bytecode. New op `CALL_BUILTIN nameConst argc` pops argc,
    calls the globals builtin. **Runtime-dependent branch of `seriesNameOf`** (`EIdent` that is
    `harness.isAuxSeries` and unshadowed) is NOT statically decidable ⇒ throw `VmUnsupported`
    (keep the boundary deterministic; don't guess).
  - **`__cs` CROSS** (`crossover`/`crossunder`/`rising`/`falling`): interp evaluates args with plain
    `evalExpr` (NOT series-name resolution), so `crossover("close", …)` passes the STRING "close"
    and `TradeBuiltins.crossoverCS(harness, csId, a, b)` resolves it internally. New op
    `CROSS csId fnCode argc` → emit args via normal `expr()`, then call the matching `*CS` with the
    `CallsiteIds` id as an immediate. Mirror the exact default-arg handling in
    `MuseInterp.evalExpr`'s `__cs` case (rising/falling have an optional 3rd arg defaulting 0).
  - **`__scr` SERIES** (`macd`/`bbands`/`stoch`, multi-output): `harness.indCols.scratchObj(scrId)`
    then `TradeBuiltins.macd/bbands/stoch(harness, …, scrOut)`. Fewer genomes — do after CROSS.
  - **`LOOKBACK`** (`series[n]` / `ELookback`): `evalLookback` → for `EBarField|EIdent` name →
    `harness.seriesLookback(name, n)`; for `ECall`/other → `harness.withSeriesOffset(n, () -> eval)`.
    Bar-field/ident case is easy; the call/offset case needs a VM re-entrancy shim ⇒ can start with
    the bar-field/ident case and `VmUnsupported` the offset case.
  - **Order per sub-op:** CROSS (unlocks the seedFromIndicators corpus with CALL_BUILTIN) → then
    LOOKBACK (bar-field case) → then `__scr` SERIES. Watch V2's `fallback` drop, `diverged` stay 0.
  - **Parity trap:** `MuseVmOps` is copied from interp privates; any builtin that internally uses
    `Math.exp`/`log` must already route through `DetMath` on the interp side — the VM calling the
    SAME builtin inherits that, so no new risk, but verify on the corpus (V2), don't assume.
- [x] **V4. Coverage measured on an EVOLVED population** (`TestVmParityCorpus.testEvolvedGenomesNeverDiverge`).
  4 rounds of `Variation.pointMutate`/`subtreeCrossover`/`mutate` from real seeds → **2430 evolved
  genomes: identical=2257 (92.9%), fallback=128 (5.3%), interpError=45, diverged=0.** So the VM already
  covers ~93% of a realistically-evolving population with ZERO divergence under mutation stress — the
  V5 oracle flag will usefully hit the fast path. The 5.3% fallback = genomes that grow out-of-subset
  constructs (loops/match/objects/user-@indicators/offset-lookback); chase those later only if V6
  shows the residual interp cost matters. No further broadening needed before V5.
- [x] **V5. Oracle flag. DONE** (`2f709f1`). `Fitness.preferVm` routes `evaluate()` through the
  bytecode VM (`evaluateVm`, `MuseChunk` cached by structural key) with interp fallback on the
  out-of-subset tail. `CorpusEvoRun --vm` enables it AFTER a startup `vmParityCheck` that evaluates
  gen-0 seeds through BOTH tiers and ABORTS on any trades/finalEquity-bit mismatch. **Correctness
  crux:** extracted `MuseCompiler.lower()` (the shared class/template/module/series-lowering +
  ConstFold/CSE/CallsiteIds pipeline) so `evaluateVm` consumes the SAME lowered AST the interp does —
  without it the VM saw raw `crossover("close", …)` string args (crash on JVM, divergence on JS).
  Self-check on real gen-0 seeds: **63/63 covered byte-identical to interp**, 1 fallback (invalid-param
  genome that errors in interp too). Full JS suite green (75,093).
- [x] **V6. Measured. Verdict: PARK at the flag (modest win, parity sound).** A/B at pop=80/gens=30/
  seed=42/NVDA: **warm s/gen 3.14 (baseline) → 2.97 (`--vm`), ~5% faster; total wall 163.8s → 151s.**
  - **Parity is SOUND.** The A/B's per-gen search lines diverge at ~gen 13 — but a 2× baseline
    determinism check (same seed, no `--vm`) **diverges from ITSELF at gen 8**: the multi-threaded run
    is not bit-reproducible (async attr-pool workers; `ReproStamp`'s "bit-identical" claim doesn't hold
    under threads — a pre-existing finding, not caused by the VM). The `--vm` arm actually tracked
    baseline *longer* (gen 13 vs 8), i.e. within the run's own noise band. VM parity rests on the
    controlled gates (self-check 63/63, corpus 83/83, evolved 2430 @ diverged=0), which are exact.
  - **Speed is modest and expected.** ~5% warm is exactly what the spec predicted: the oracle is
    already cache-dominated (§7), so the Dynamic-stack P0 VM can only attack the miss fraction. P0 was
    never the speed milestone. Given a single nondeterministic A/B can't nail 5% tightly, **do NOT
    promote `--vm` to default on this evidence — keep it behind the flag (default OFF).**
  - **The real win is P1** (unboxed operand stack). V6 makes it justified: correctness + the plumbing
    are proven end-to-end; the speed is left on the table by the boxed Dynamic stack. Pursue P1 next.

## P1 — only after V6 shows a real win

- [ ] **P1.1** Unboxed numeric operand stack (the actual speed).
- [ ] **P1.2** Superinstructions (fuse `LOAD_LOCAL`+cmp etc.) + inline caches where dispatch shows up.
- [ ] **P1.3** Compiled-`MuseChunk` cache by structural key beside `EvoCache` (currently facts-only;
  nearest precedent is `Fitness.fnCache`, in-memory per run).

## P2+ — gated, not scheduled

- [ ] **P2** Tier B Truffle Bytecode-DSL interpreter — only if Tier A is proven AND the per-genome
  WASM emit/instantiate residual still matters. Kill-criterion per spec §9.
- [ ] **P3** Long-tail coverage (objects/arrays/classes/match; generators stay interp on Tier A).
- [ ] **P4** Retarget JS/WASM emitters from the shared IR — do not destabilize audited WASM parity
  before Tier A has earned default status.

## Standing risks (check on every PR touching the VM)

- `MuseVmOps` value semantics are **copied** from `MuseInterp` privates, not shared — drift between
  them is silent until parity catches it. Any interp semantics change must touch both or fail V2's gate.
- Locals shadowing bar fields, multi-arg orders, unknown identifiers: currently hard `VmUnsupported`
  throws — keep them loud, never "best effort."
- Transcendentals route through `DetMath` only (`exp`/`log`); plain `+ - * /` are IEEE-identical
  across targets and stay native.

## Explicitly NOT next

- Truffle/Java Tier B scaffolding
- Shared-IR retargeting of the JS/WASM emitters
- Unboxed fast path before V3–V6
- Any speedup claim against 22.9 s/gen
