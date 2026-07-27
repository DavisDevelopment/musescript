# MuseScript + evolution — polish-pass notes (hand-off to Cursor)

**Date:** 2026-07-26
**Author of this pass:** Claude (Opus 4.8), read-only review + JIT-guide expansion
**Scope reviewed this session:** the JIT hot path — `musescript/indicators/{RingBuffer,GrowableVec,FloatSeries}.hx`,
`musescript/harness/OrderSim.hx`, `musescript/evo/nma/{NmaEval, NmaKernel*, NmaFusedLogicKernel,
NmaFixedColumnKernel, NmaKernelWarm, NmaWasmFusedEmitter, NmaFuseHost}.hx`, `musescript/compile/JsBackend.hx`
(setup + arity fast tables), `musescript/builtins/TradeBuiltins.hx` (stats reducers),
`musescript/evo/NmaNodeBench.hx`, `musescript/evo/SymbolSelector.hx`, plus anti-pattern greps across
`evo/nma`, `indicators`, `harness`, `compile`, `builtins`, `parse`, `interp`.

**What I changed this session (already committed to the tree, not to git):**
- `musescript/evo/nma/JIT_AUTHORING_GUIDE.md` — added **§35–§38** (V8 tier ladder; Smi/HeapNumber +
  elements kinds; Node/Electron process & concurrency model; V8 deopt/measurement tooling) and
  registered them + the owed V8 audit tool in the Document-maintenance checklist. This is the
  "flesh out the Node/Electron+V8 stack" ask. Everything else below is **notes only — nothing else
  in code was modified.**

---

## 0. Headline (read this first)

**The hot path is already rock-solid.** The team has clearly fought and won the boxing war on the JVM
side: `NmaEval`, `OrderSim`, `RingBuffer`/`GrowableVec`/`FloatSeries` are textbook — kind-switch to
`final` leaves, indexed `while` loops, hoisted op-switches, bulk `setAt`+`commitLength`, NaN
sentinels, `Float64Array` under `#if js`, documented parity quirks. There is **very little
low-hanging hardening fruit in the hot path itself.** Do not let anyone "refactor for readability"
here without a JIT audit — that is how these wins get quietly reverted.

So the real value in a polish pass is **(a) the handful of genuine small findings below, (b) the
systematic verification-owed items the guide itself already flags, and (c) closing the V8/Node/Electron
side up to the JVM side's rigor.** Ordered by ROI, not severity.

---

## 1. Genuine findings (concrete, file:line, verified this session)

### 1.1 [LOW] `TradeBuiltins.zscore` uses `for..in` over `Array<Float>` — boxes on JVM
`musescript/builtins/TradeBuiltins.hx:995-1002`
```haxe
for (x in xs) mean += x;        // boxes every element on the JVM target (JIT guide §3.3)
for (x in xs) var_ += (x - mean) * (x - mean);
return [for (x in xs) std == 0 ? 0 : (x - mean) / std];
```
`xs:Array<Float>`, and `for (v in Array<Float>)` normalizes through `java.util.Iterator.next():Object`
→ boxes. **Not on the NMA columnar path** (NmaEval has its own arith), so this only bites hand-written
/ interp strategies that call `zscore` per bar. Fix = indexed loops (`for (i in 0...xs.length)`).
Low priority, but it's a §3.3 violation sitting in a public builtin; worth fixing for consistency and
because `zscore` over a rolling window *is* a per-bar shape in some strategies.
*Sweep for siblings:* grep found the rest of `TradeBuiltins`' hot reducers already indexed
(`min`/`max`/`ema` at 452/461/594 use `for (i in start...a.length)`), so this is the lone straggler in
that file. Worth a quick grep for `for (x in xs)` / `for (v in <arr>)` in other builtins before closing.

### 1.2 [INFO] `NmaFuseHost` JS path has a hard tape-length ceiling (~43k bars) — silent perf cliff, not a bug
`musescript/evo/nma/NmaFuseHost.hx:124-130` (`ensureJsMem`)
The fuse WASM module is fixed at **16 pages ≈ 1 MiB** (`NmaWasmFusedEmitter.emitModule`, line 25),
which holds 3×f64 columns for n ≲ 43k bars. Above that, `ensureJsMem` **throws** rather than growing
memory. The throw is caught in `fuse()` → returns null → `fuseFallbacks++` → falls back to `logic2`,
so it **degrades gracefully (correctness is fine)** — but every fuse call on a long tape silently
becomes a throw-and-fallback, i.e. a perf cliff with no signal except the `fuseFallbacks` counter
climbing. Two options for Cursor:
  - (a) grow-and-reacquire: `memory.grow` then rebuild the `jsView:Float64Array` over the new buffer
    (JIT guide §5.2's "reacquire `exports.memory` after grow" — same rule applies to the JS host), or
  - (b) size the module pages from the max expected tape length at init and document the ceiling.
Note this is dormant by default: `NmaFuseHost.enabled = false` (line 15), so the fuse host doesn't run
unless a caller flips it on (CorpusEvoRun sets `minLength = 8192`). Flag it before anyone turns fusion
on for large-tape runs.

### 1.3 [INFO] `NmaFuseHost.fuseJvm` does per-element polyglot boundary writes — the reason fusion is gated to `minLength ≥ 8192`
`musescript/evo/nma/NmaFuseHost.hx:170-186`
```haxe
for (i in 0...n) {
    jvmMem.writeBufferDouble(order, haxe.Int64.ofInt(i * 8), a.at(i));      // 1 polyglot call / elem
    jvmMem.writeBufferDouble(order, haxe.Int64.ofInt((n + i) * 8), b.at(i)); // + 1 more
}
// ... + n readBufferDouble on the way out  => ~3n host↔guest crossings per fuse
```
This is exactly the "host-boundary copy dominates" cost the class comment cites for defaulting
`minLength` to 8192. Each `writeBufferDouble`/`readBufferDouble` is a Haxe→Value polyglot crossing +
an `Int64.ofInt` alloc per element. JIT guide §4.3 ("reuse argument arrays at polyglot boundaries")
says minimize crossings. **Idea:** stage the two input columns into a single Haxe `haxe.io.Bytes`
(or a `double[]` the host can bulk-copy) and do **one** bulk write into wasm memory + **one** bulk
read out, instead of 3n calls. If that lands, the `minLength` gate can likely drop a lot, making
fusion pay off on ordinary-length columns instead of only 8k+ tapes. **Measure before/after** — this
is the kind of polyglot-boundary change §9.1 (`jit_audit_run.sh`) exists to validate.
(The JS path — `fuseJs`, lines 132-144 — is fine: `jsView[i] = a.at(i)` is a plain typed-array write,
not a boundary call, since `jsView` is a `Float64Array` over wasm memory.)

### 1.4 [TRIVIAL] `NmaNodeBench` dirty-spine flag is a confusing double-negative
`musescript/evo/NmaNodeBench.hx:32`
```haxe
var dirtySpine = !argFlag("--no-nma-dirty-spine") && argFlag("--nma-dirty-spine");
```
Behaviour is correct (opt-in; `--no-` wins if both passed) but reads as a bug at a glance and the
`!argFlag("--no-...")` term is dead unless both flags are passed. Reorder for readability:
`argFlag("--nma-dirty-spine") && !argFlag("--no-nma-dirty-spine")`, or just add a one-line comment.
Trivial; mentioned only so a reviewer doesn't "fix" it into an actual behaviour change.

### 1.5 [INFO] `RingBuffer.at` / `GrowableVec` correctness spot-check — clean
`RingBuffer.at(i)` = `data[(head + length - 1 - i + capacity) % capacity]` uses one `%` per access
(unavoidable for arbitrary period; can't mask a non-power-of-2 capacity). Fine. Iterators allocate an
array per call but are documented cold-path only. `GrowableFloatImpl.grow()` can't div-by-zero (ctor
floors capacity at 8). No action — recorded so the next reviewer can skip re-deriving it.

---

## 2. Systematic items the codebase already owes itself (higher ROI than §1)

These come straight from the JIT guide's own "Document maintenance" list, the roadmap hooks, and
`PLAN_EVO_SPEED.md`. They are the real "make it near-native and prove it" work.

### 2.1 [HIGH] Multi-thread `--nma` determinism probe is still OWED
Guide §27/§32 + Document-maintenance. The JVM worker-pool + NMA statics hazards are *closed*
(`EvoLock` guards epoch interning / credit bank / column caches / `fnCache`; dirty-spine is disabled
above one worker). But the pool is **not proven**: there is no green **N genomes × M threads × K reps,
identical-to-serial** probe. Until that exists, any `--nma --threads >1` result is trust-me. This
gates calling the parallel NMA path production-ready. **This is the single most important correctness
task in the evo stack.** (Same shape as PLAN_EVO_SPEED P3's probe; throwaway, delete after.)

### 2.2 [HIGH] `NmaKernel` real emitter — status is "attach-only WAT, host dormant by default"
Current reality (verified):
  - `NmaKernel` interface = real; concrete impls `NmaFixedColumnKernel` (test/cache) and
    `NmaFusedLogicKernel` (**megamorphic — A/B only, `installMegamorphKernel=false` by default**).
  - The **real** P4 path is `node.kernelWat` + `NmaFuseHost` (genuinely assembles WAT →
    `WebAssembly.Instance` on JS / GraalWasm on JVM and runs `fuse_and_cols`/`fuse_or_cols`).
  - BUT: `NmaKernelWarm.enabled = true` attaches WAT after 3 evals, while `NmaFuseHost.enabled = false`
    by default → in default runs the WAT is attached but the fuse **never runs** (`shouldFuse` returns
    false), so `evalBool`'s kernelWat branch falls through to plain `logic2`. **The fusion frontier is
    wired end-to-end but dark by default.** Only BAnd/BOr are fused; every other kind still interprets.
Owed: (a) close §1.2/§1.3 so the host is cheap enough to default-on; (b) extend fusion past 2-input
logic to the arith/compare/cross/trend arms (the WASM emitter only emits AND/OR today); (c) a real
JVM-fused specialized walker (`@:build`) as the guide's §2.4 tier-2, currently aspirational text.

### 2.3 [MED] Shared hyper-opt vector type is still OWED (`SymbolSelector`)
`musescript/evo/SymbolSelector.hx:21` still carries the TODO: `weights`/`features` should be the
shared GraalVM+JS-optimized vector type used "throughout the codebase for such use cases", and they're
still plain `Array<Float>` (line 24). The right type already exists — `FloatSeries` / `GrowableVec`
(unboxed `double[]` on JVM, `Float64Array` on JS). This is a "land the one type, replace the
`Array<Float>` call sites" job (guide §3.2 / §13 / anti-pattern #15). Do it **once**, everywhere, not
a third ad-hoc container.

### 2.4 [MED] `PLAN_EVO_SPEED.md` P4 residuals — measure, don't assume
- **LastTier A/B**: `engine.LastTierCompilationThreshold=2000000000` currently disables last-tier
  Truffle WASM JIT. Owed a same-seed warm A/B (guide §5.3). Keep whichever wins; write it down.
- **In-process WAT on JVM**: `NmaFuseHost.initJvm` already assembles WAT in-process via
  `WatAssembler.assemble` on the JVM target (lines 148-153) — so the "kill the Python `wat2wasm`
  subprocess" P4.2 item is **partly proven possible** (the assembler compiles on JVM). Check whether
  the per-gen corpus-evo WAT path still shells out to `tools/wat2wasm_batch.py` and, if so, route it
  through `WatAssembler` too.
- `--enable-native-access=ALL-UNNAMED` to silence Truffle warnings (zero perf, log hygiene).

### 2.5 [MED→doctrine] The V8/Node/Electron side owes measurement (I wrote the doctrine; the numbers are owed)
From the new guide §35–§38 (all framed honestly as "doctrine, not yet in a repo audit"):
  - **`scripts/v8_deopt_run`** — a `jit_audit_run.sh` twin: run `NmaNodeBench` under
    `--trace-deopt --trace-opt`, summarize top deopt sites + any hot `musescript.*` fn that never
    reached TurboFan. **Owed tool.** Interim: `node --trace-deopt build/js/nma-node-bench.js … 2>&1 |
    grep -i musescript`.
  - **First TurboFan-warm number** on `NmaEval`/`OrderSim` under Node, verified with
    `%GetOptimizationStatus` (§38.1), so the JS floor is a real steady-state number not a Sparkplug/
    Maglev artifact.
  - **The same measured on the shipped Electron V8**, not just plain Node (§35.2) — the desktop app's
    evo runs on Electron's V8, which is a different build. `build-nma-node-bench.hxml` is the floor.
  - **Persistent `worker_threads`/`utilityProcess` evo pool** (§37.1) as the V8 twin of the JVM
    `sys.thread` pool — send the tape once at spinup, message-pass genome descriptors/results. This is
    how the 85%+ near-native target gets its parallelism on the desktop/Node target; today
    `NmaNodeBench` is single-threaded by design.

---

## 3. Module-by-module status (what I actually looked at)

| Module | Verdict | Notes |
|---|---|---|
| `indicators/RingBuffer.hx` | ✅ exemplary | `@:multiType` Float fast path, `Float64Array` on JS, cold iterator documented. No action. |
| `indicators/GrowableVec.hx` | ✅ exemplary | Same. `setAt`/`commitLength` bulk-fill API, `clear`/`ensureCapacity` for sim recycling. No action. |
| `indicators/FloatSeries.hx` | ✅ exemplary | Owned vs aliased (`fromVector` zero-copy prefix) modes; JS `Float64Array` owned / `Vector` alias split is deliberate. No action. |
| `harness/OrderSim.hx` | ✅ exemplary | NaN qty sentinel, `reserveEquity`, `!trackCurve` return-stream path, weighted-avg entryPrice, margin/risk caps documented from real exploit post-mortems. No action. |
| `evo/nma/NmaEval.hx` | ✅ exemplary | THE hot eval. Kind-switch + `final` cast, indexed `while`, hoisted op switch, RingBuffer trend, documented min/max parity quirk. **Reference file — copy its shape.** |
| `evo/nma/NmaFuseHost.hx` | ⚠️ see §1.2, §1.3 | Working WASM fuse, but JS mem ceiling + JVM per-element boundary writes. Dormant by default. |
| `evo/nma/NmaWasmFusedEmitter.hx` | ⚠️ AND/OR only | Real WAT emitter, but only 2-input logic; arith/compare/cross/trend arms not emitted (see §2.2). |
| `evo/nma/NmaKernel*.hx` / `NmaKernelWarm.hx` | ⚠️ frontier | Interface + placeholder impls; WAT-attach on by default but host off by default (§2.2). |
| `compile/JsBackend.hx` (setup + fast tables) | ✅ correct | Heavy `Reflect.setField` is **one-time API-object construction (cold)**; `invoke0..4` + `cache0`/`fast0` memo is the hot arity fast path (guide §6.2). Did **not** read all 63KB — only setup + fast-table region. |
| `builtins/TradeBuiltins.hx` | 🟡 one straggler | §1.1 `zscore` `for..in`. Rest of hot reducers already indexed. |
| `evo/NmaNodeBench.hx` | 🟡 §1.4 | Solid V8 bench; confusing flag expression only. It's the right harness for §2.5 measurement. |
| `evo/SymbolSelector.hx` | 🟡 §2.3 | Still `Array<Float>` with the owed shared-vector-type TODO. |

**Not reviewed this session (candidates for the next pass):** `NmaFitness.hx` (27KB — the fitness
barrier, highest-value unread file), `NmaAttr.hx`/`NmaCreditBank.hx` (attribution — §33 says it's
~52% of a generation), `compile/JsEmitter.hx` (`ECall` arm / arity emit), `compile/WasmEmitter.hx` +
`WatAssembler.hx`, `evo/EvolutionEngine.hx` + `Variation.hx` (§33: `step` is 84% of the generation and
single-threaded — **the actual ceiling; the highest-leverage place to look next**),
`harness/PanelFeed.hx` (universe scanner hot path).

---

## 4. Forward ideas (unprioritized, for discussion — not commitments)

1. **The ceiling is `EvolutionEngine.step`, not evaluation.** Guide §33 measured `step` at 84% of a
   generation, single-threaded, and even with attribution *off* it's 62%. Every eval/kernel/container
   optimization is capped at ~1.2× by Amdahl. **If you want a big multiple, the next real project is
   making variation/attribution parallel or cheaper, not faster columns.** Read `Variation.hx` /
   `EvolutionEngine.step` with `--phase-profile` open before optimizing anything else.
2. **Default-on the fusion path** once §1.2/§1.3 make the host cheap — then extend `NmaWasmFusedEmitter`
   to fuse *chains* (a whole bool subtree → one WASM function), which is where WASM fusion actually
   beats interp (amortize the boundary copy over many ops, not one AND).
3. **A single "near-native %" dashboard.** The 85%+ target needs a number. Define it: e.g.
   (hand-written WASM/JVM kernel bars/s) vs (NMA columnar bars/s) per op family, tracked in one
   generated table from `EvoBench` (JVM) + `NmaNodeBench` (V8). Right now "near-native" is a vibe;
   make it a CI-tracked ratio so regressions are visible.
4. **JS-worker evo pool is *safer* than the JVM pool** (§37.1): separate isolates ⇒ §27's shared-static
   race class *cannot occur*. If the multi-thread NMA determinism story stays hard on the JVM (§2.1),
   the desktop/Node target could get parallel evo *first* via message-passed workers, and the JVM pool
   follows once its probe is green.
5. **Elements-kind / Smi audit on the JS emit** (§36): once `v8_deopt_run` exists, add a pass that
   greps the emitted JS for holey-array creation (`new Array(n)` + sparse fill, `arr[i]=null`
   placeholders on numeric arrays) — the V8 twin of the JVM boxing audit.

---

## 5. How to verify anything in here (so Cursor doesn't ship on trust)

- **JVM hot-path change:** `scripts/jit_audit_run.sh build/jvm/evo-bench.jar musescript.evo.graal.EvoBench --pop 40 --gens 10`
  → read `build/graal/jit-audit/<main>/summary.txt` for deopt/inline regressions. Same-seed A/B for
  wall time. **Never rebuild a jar a live evo process has open** (PLAN_EVO_SPEED hard rule).
- **V8 change:** `haxe build-nma-node-bench.hxml && node build/js/nma-node-bench.js --pop 256 --gens 6`
  → compare `scoreMs`/`wallMs` and confirm `nmaOk`/`nmaFall` don't move for a zero-behavior-change
  phase. Warm before timing (§35.1). Add `--trace-deopt` for shape bugs.
- **Parity is mandatory** (guide §22): a speed change that isn't bit-exact (same-seed evo lines
  identical) for a "zero behavior change" phase is a bug, not a win. min/max parity quirk (§28) is the
  cautionary tale — "more correct" is a divergence.

---

*One-line summary for the standup:* the hot path is already near-native-grade on the JVM and the
containers are right on both targets; the wins left are **(1) prove the parallel NMA path (§2.1),
(2) light up + extend WASM fusion (§2.2 + §1.2/§1.3), (3) bring the V8/Node/Electron side up to the
JVM side's measurement rigor (§2.5, doctrine now written in guide §35–§38), and (4) attack the real
84%-of-generation ceiling in `EvolutionEngine.step` (§4.1)** — not to squeeze the already-tight columns.
