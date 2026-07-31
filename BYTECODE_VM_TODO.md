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
- [ ] **V3. Indicator subset — the real unlock.** `LOOKBACK`, `SERIES id n`, `CROSS id n` mirroring
  interp semantics exactly: callsite-keyed slots via `CallsiteIds` ids, same
  `HarnessContext.seriesBuffers` / `IndicatorInstance.stateFor` / `TradeBuiltins.*CS` state.
  Until this lands, nearly every real evo genome misses the VM.
- [ ] **V4. Prelude/body coverage, corpus-driven.** Broaden statements/exprs only where corpus
  genomes actually hit `VmUnsupported` (measure the fallback rate; don't chase the full language).
- [ ] **V5. Oracle flag.** `--vm` / `preferVm` on `Fitness.evaluate`/`evaluateCompiled` (same
  try-fast-tier/fallback pattern as `preferNma`), threaded from `CorpusEvoRun.evalFn`. Default OFF.
- [ ] **V6. Measure, then decide.** (a) per-eval Tier A vs tree-walk interp on cache misses;
  (b) end-to-end warm s/gen A/B vs ~4.35 on the canonical baseline (pop=80, gens=30, NVDA,
  IS=5161, 20 bps, seed 42, warm gens 6–30). Record both here. Promote to default or park —
  no promotion on faith.

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
