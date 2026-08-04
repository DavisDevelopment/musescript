# Audit Triage & Delegation Plan

Source: holistic audit handed off 2026-08-02/04. This document re-verifies each finding
against the live code (file:line cited), buckets them, and lays out an assignable work
program. No production code was modified to produce this document — verification only,
plus two background planning sub-agents (see §4).

---

## 1. Verification pass

### Finding #1 — `min(a,b)`/`max(a,b)` silently drop the 2nd arg — CONFIRMED, exact

- `musescript/builtins/TradeBuiltins.hx:277-282` — `min`/`max` are registered as **single-arg**
  iterable reducers:
  ```
  vars.set("min", function(xs:Dynamic) { return IterDriver.min(MuseIters.from(xs)); });
  vars.set("max", function(xs:Dynamic) { return IterDriver.max(MuseIters.from(xs)); });
  ```
  Called as `min(a, b)`, the second argument is silently dropped; `MuseIters.from(a)` treats
  the first arg as a one-element iterable, so `min(a,b) → a` always.
- `musescript/evo/nma/NmaEval.hx:313-326` — the NMA (native/bytecode) backend **deliberately
  replicates** this behavior for cross-backend bit-exact parity. The comment there is explicit:
  fixing `Expand` (the renderer) would change live production behavior, so NMA mirrors the bug
  rather than silently diverging. Case `"min" | "max"` (line 321) just copies operand `a`.
- `musescript/evo/Palette.hx:84` — `ARITH:Array<String> = ["+", "-", "*", "min", "max"]` is the
  arithmetic-operator palette the **evolution engine** draws from when synthesizing/mutating
  expressions. 2 of 5 ops (40%) are therefore identity-on-first-arg no-ops whenever the
  evolved expression uses the 2-scalar-arg form (the common case for an arithmetic palette).
  Audit's "~40% of arithmetic palette is dead" figure is arithmetically exact (2/5) — confirmed.

**Verdict: reproduces exactly as described — with an important correction found by the WP-A
planning sub-agent (§4): the "three-backend-consistent" framing is WRONG.** WASM already does
true 2-arg min/max (`musescript/compile/WasmEmitter.hx:403-406`,
`musescript/compile/StrategyWasmEmitter.hx:1383-1388` both special-case `args.length==2` and emit
real `f64.min`/`f64.max`), and the evolution engine's own constant-folder
(`musescript/evo/Simplify.hx:267,285-286`) already assumes/uses real `Math.min`/`Math.max`. So
parity is **already broken today** between WASM+Simplify (correct) vs. interp+JS+NMA (buggy) —
this is not a case of "don't fix it, it'd break parity," it's "parity is already broken, and the
majority of backends (interp, JS, NMA — the ones actually used for evolution and live scoring) are
on the wrong side of it." This meaningfully changes the framing of the human decision in §3: doing
nothing does not preserve consistency, it preserves an existing 3-vs-2 split. Additionally, the
sub-agent found a **live production bug independent of the evolution-parity question**:
`kernels/volume_profile_v1.ms:51` — `allocation = min(remaining, vol * overlap / (hi - lo));` —
silently always evaluates to `remaining` (the cap is a no-op), inside real auction/volume-profile
allocation logic (`musescript/ew/auction/VolumeProfile.hx`). This is real and live — not evo-only.

### Finding #2 — `resetCrossState()` is a manual ritual, not automatic — CONFIRMED, exact

- `musescript/builtins/TradeBuiltins.hx:1095` — `resetCrossState()` defined; clears static
  callsite-keyed state backing `crossover`/`rising`/`falling`/`bars_since`.
- **~70 manual call sites** found repo-wide (audit said "20+" — actual count is higher), spanning
  tests, examples, CLI, evo engine, harness. Representative: `musescript/cli/GeneRunner.hx:421`,
  `musescript/harness/HarnessContext.hx:326`, `musescript/evo/Fitness.hx:451,772`,
  `musescript/evo/GenomeStepper.hx:94`, `musescript/runtime/MuseRuntime.hx:107,210,322,956`.
- `musescript/harness/HarnessContext.hx:111` `runBacktest()` — read in full (lines 111-132) —
  does **not** call `resetCrossState()` anywhere in its body.
- `musescript/harness/HarnessContext.hx:310` `resetForTrial()` — a **separate, opt-in** method —
  does call it, at line 326. But nothing forces callers to invoke `resetForTrial()` before
  `runBacktest()`; they're independent methods.
- `musescript/interp/MuseInterp.hx:523` `bindBar()` — called once per bar — only calls
  `TradeBuiltins.beginBar()` (a different, per-bar-not-per-run reset) plus
  `harness.indCols.beginBar()`. No cross-state reset here either.

**Verdict: reproduces exactly as described.** The primary run-entry point genuinely has no
built-in safety net; every existing caller that's "safe" today is safe only because *someone
remembered* to call `resetCrossState()`/`resetForTrial()` first. New integrations are one missed
call away from stale-state contamination on bar 1..N of a fresh run.

### Finding #3 — bare `atr(n)` silently NaNs — CONFIRMED at the signature level, one nuance flagged

- `musescript/builtins/TradeBuiltins.hx:491` — `atr(harness, src, len)` is a genuine 2-positional-arg
  function (beyond the bound `harness`), i.e. exposed to callers as `atr(src, len)`.
- `musescript/types/BuiltinSigs.hx:101,630-632` — registered via `ind("atr")` →
  `fun(name, [TSeries, TWindow], TSeries)` with `minArgs` defaulting to `args.length == 2`.
  So a **type-checked** call path should reject `atr(14)` outright as under-arity, not silently NaN.
- **Nuance**: the audit's claim that `atr(13)` in the corpus "silently returns NaN" implies the
  1-arg call is *accepted* somewhere (i.e. some entry path skips/relaxes the arity check, or an
  older interp-only calling convention lets `src=13` bind and `len` come back `null`/`0`, tripping
  `if (m < len) return Math.NaN` at line 504). I did not find the specific bypass path in this pass
  — flagging as **needs a 15-minute runtime repro** (run one corpus file with `atr(13)`) before
  writing the fix, rather than assuming the exact failure mode. The *comparison* to `stoch`/`donchian`
  (`musescript/types/BuiltinSigs.hx:129,169`) accepting an implicit-OHLC single/reduced-arg form is
  confirmed real and is a reasonable template for the fix either way.

**Verdict: reproduces at the signature/registration level; the exact runtime failure mode (type
error vs. silent NaN) needs a 1-file repro before the fix PR, not before triage.**

### Finding #4 — `prob_up` almost-renderable now that `count_true` exists — CONFIRMED, exact

- `musescript/evo/Expand.hx:124` and `:157` — both throw the exact string
  `'Expand: prob_up is not yet renderable (needs a builtin) for "${decl.name}"'`, at exactly the
  cited lines.
- `musescript/builtins/TradeBuiltins.hx:138-141`, `musescript/types/BuiltinSigs.hx:162-164` —
  `count_true` is confirmed variadic bool→scalar (`fun("count_true", [TBool], TScalar, 1, true)`,
  minArgs 1, varArgs true), already covering exactly the "bool→float coercion" gap the `Expand.hx`
  comment (line 122) says `prob_up` is blocked on. `TestConfirmationVote.hx` shows it fully tested
  and shipped.

**Verdict: reproduces exactly. This is genuinely a small unlock** — the blocking primitive already
exists and is tested; `Expand.hx` just hasn't been updated to use it for `prob_up`.

### Finding #5 — interp-only multi-output cross-field quirk — PARTIALLY CONFIRMED (mechanism located, misbehavior not re-derived in this pass)

- `musescript/interp/MuseInterp.hx:852` — confirmed a `case EMeta("__scr", [EConst(CInt(scrId))],
  ECall(EIdent(scrName), scrArgs))` scratch-path exists exactly where cited, handling multi-output
  builtin calls specially via a callsite-scratch id. This is a plausible mechanism for the
  `donchian(20).mid` vs `.upper` divergence the audit describes (two field-reads of the same call
  racing over/reusing one scratch slot).
- I did not execute a repro (e.g. `donchian(20).mid` and `donchian(20).upper` read in one
  expression across interp/js/wasm/vm) to confirm the actual divergence in this pass — this is
  the lowest-severity finding and the audit already scoped it as "before promoting a `candle(i).{…}`
  struct form," i.e. not urgent.

**Verdict: mechanism located at the cited line; behavioral repro not re-run — low priority, low risk of being wrong given the audit's specificity.**

### Informational items — CONFIRMED as out-of-scope

- Build-red from a concurrent collaborator: `fs_read_bytes` / `BuiltinSig` gap confirmed present
  in `musescript/builtins/MuseHost.hx`, `musescript/types/PluginCapabilities.hx`,
  `musescript/builtins/FsBuiltins.hx`, and WAT-assembler-related scratch output files
  (`scratch/suite*.out`) show the `i64` unsupported-value-type symptom. Real, but explicitly
  not ours — no work package created for it; noted here only so it isn't rediscovered and
  accidentally "fixed" by someone on this triage list.
- `musescript/compile/TemplateExpand.hx` exists (confirmed path, differs slightly from audit's
  cited `musescript/evo/TemplateExpand.hx` — it's under `compile/`, not `evo/`); stale-TODO claim
  not independently re-read in this pass, treated as benign per audit.

---

## 2. Buckets

Scheme: **severity** (does it silently produce wrong numbers vs. throw/degrade gracefully) ×
**effort** (S = <1 day, M = 1-3 days, L = needs a re-baseline campaign) × **blast radius**
(Evo-repro = changes evolved-genome fitness history; Prod-behavior = changes live backtest output
for hand-written strategies; Docs/DX = no behavior change, just unlocks/clarity).

| # | Finding | Severity | Effort | Blast radius | Dependencies |
|---|---|---|---|---|---|
| 1 | `min`/`max` 2-arg drop | High (silent wrong numbers) | M (fix is small; re-baseline is the cost) | **Evo-repro + Prod-behavior** — every evolved genome and hand-written strategy using 2-arg `min`/`max` changes output | Needs human GO on re-baselining (see §3) before merge |
| 2 | `resetCrossState()` manual ritual | High (silent stale state, but only on *new* callers) | S (the fix itself) | Prod-behavior for *future* integrations; near-zero for existing ~70-callsite-covered paths if audited safe | Needs confirmation existing hot paths (Fitness.hx, GenomeStepper.hx, MuseRuntime.hx) already call it correctly (sub-agent investigating, §4) |
| 3 | bare `atr(n)` NaN | Medium (silent bad indicator value, narrower surface than #1) | S–M (fix small; needs 15-min repro first to nail exact failure mode) | Prod-behavior only for strategies/corpus entries actually using the buggy 1-arg form | None — independent |
| 4 | `prob_up` unlock via `count_true` | Medium, but upside not risk (currently a hard throw, not wrong numbers) | S | Docs/DX + unlocks a new evolution palette feature (net-new capability, not a behavior change to anything existing) | None — independent, low-risk, good "quick win" |
| 5 | multi-output cross-field interp quirk | Low (interp-only, narrow expression shape) | S (bugfix) once repro'd; needs a repro script first | Prod-behavior, interp backend only, for a rare expression shape (`donchian(20).mid` and `.upper` both read in one expression) | None — independent, but do NOT let it block promoting `candle(i).{…}` struct form (per audit's own note) |
| Info | Build-red from concurrent collaborator | N/A | N/A | N/A | Not our package — do not touch `fs_read_bytes`/`BuiltinSig`/WAT i64 files |
| Info | Stale TODOs | N/A | N/A | Docs only | No package |

---

## 3. Delegation plan — work packages

**WP-A: Fix bare `min`/`max` 2-scalar-arg semantics (Finding #1)**
- Scope (revised per sub-agent investigation, §4): WASM (`WasmEmitter.hx:403-406`,
  `StrategyWasmEmitter.hx:1383-1388`) and the evo-engine constant-folder
  (`Simplify.hx:267,285-286`) **already implement correct 2-arg min/max** — they are not part of
  the fix. The actual fix touches 3 files: `TradeBuiltins.hx:277-282` (interp — make min/max
  arity-aware), `JsBackend.hx:1600-1601` (JS backend — add a 2-scalar-arg branch before the
  reducer fallback), `NmaEval.hx:321-325` (NMA — replace the deliberate passthrough with real
  `Math.min`/`Math.max`). `Expand.hx:381` (the renderer) needs no change — it already emits
  `min(a,b)` correctly; it's the builtins underneath that were wrong.
- Recommend splitting into two sub-packages:
  - **WP-A1 (uncontroversial, do now):** patch `kernels/volume_profile_v1.ms:51`'s specific
    allocation-cap bug locally (e.g. rewrite the expression to avoid relying on shared min/max
    semantics) — this is a live production correctness bug independent of the palette-parity
    question and needs no re-baseline decision.
  - **WP-A2 (needs the decision below):** the shared `min`/`max` builtin fix across
    TradeBuiltins/JsBackend/NmaEval, plus re-baselining `TestNmaEval.hx:116-119` (asserts
    `min(11,close)==11`, must flip to true-min), `TestNmaFitness.hx:84`, and re-checking
    `TestSimplify.hx:177-180`; corpus files `corpus/parse/g000,g002,g003,g005,g006,g007,g009_musegene.ms`
    and `corpus/parse/t025_TestMain_aa7479386b.ms:8-9` use 2-arg min/max (~13 occurrences) — their
    parse-goldens are AST-only and likely unaffected, but any execution/fitness goldens for them
    need checking.
- Blocked on (WP-A2 only): **human decision** — do we want the re-baseline? See "Decision needed"
  below. WP-A1 is unblocked and can start immediately.
- Effort: WP-A1 = S. WP-A2 code fix = S (3 small, localized edits per sub-agent); re-baselining
  known tests = S-M; a full evolved-genome/fitness-campaign re-run (if judged necessary) = L.

**WP-B: Auto-reset `resetCrossState()` inside `HarnessContext.runBacktest()`/`runPanelBacktest()` (Finding #2)**
- Scope, confirmed exact by the WP-B planning sub-agent (§4): change both signatures to
  `runBacktest(onBar:Bar->Void, feed:BarFeed, ?resetCrossState:Bool = true)`
  (`HarnessContext.hx:111`) and the equivalent on `runPanelBacktest` (`HarnessContext.hx:141`),
  each adding `if (resetCrossState) TradeBuiltins.resetCrossState();` as the first line of the
  method body. Leave `resetForTrial()`'s existing call (`HarnessContext.hx:326`) in place — it's
  still the right spot for full per-trial teardown (orders/portfolio/series), the cross-state
  reset there just becomes redundant-but-harmless.
- **Confirmed safe, not a judgment call** (sub-agent verified, not just asserted):
  - Every current production hot path already calls `resetCrossState()` immediately before its
    own run — `Fitness.hx:451,772` (right before `MuseVm.runChunk`/the compiled strategy closure),
    `GenomeStepper.hx:94` (constructor, before `setupRun`), `MuseRuntime.hx:107,210,322,956` (each
    a few lines before its own `runBacktest`/`runPanelBacktest`/`runWasm` call),
    `MuseDebugSession.hx:60` (constructor; the debugger never even calls `runBacktest` — it
    manually steps bar-by-bar, so it's unaffected either way).
  - No caller found that relies on cross-state *surviving* across repeated `runBacktest()` calls
    on the same `HarnessContext` (checked `MuseRuntime.hx`'s streaming/preloaded JS/Py run paths
    and grepped for "streaming"/"live" near Harness usage) — so the opt-out param currently has
    zero real consumers; it exists purely as a documented escape hatch, not a required one.
  - `resetCrossState()` (`TradeBuiltins.hx:1095-1100`) unconditionally zeroes its state maps —
    calling it twice in a row (existing manual call + new automatic call) is a confirmed no-op the
    second time. No existing test straddles two `runBacktest` calls expecting stale state to
    survive.
  - One nuance surfaced: on the *compiled* path, per-callsite crossover/crossunder state is
    migrating to instance-scoped storage (`musescript/compile/CallsiteIds.hx`,
    `musescript/runtime/IndicatorInstance.hx`), with `TradeBuiltins`'s static maps called out
    in-code as the "legacy global slot-keyed fallback." Still real, still needs the fix — just
    worth noting this is a stopgap for the legacy/interp path, not necessarily the final home for
    cross-bar state.
- Effort: **S**, confirmed — two one-line signature changes + one guard line each.
- **No human decision needed** — the sub-agent's explicit verdict: "a safe, uncontroversial fix."
  Can ship independently of WP-A's decision.
- Can run **in parallel** with WP-A/WP-C/WP-D/WP-E; fully independent files.

**WP-C: Accept 1-arg `atr(n)` as implicit-OHLC form (Finding #3)**
- Scope: mirror `stoch`/`donchian`'s implicit-series convention so `atr(14)` binds `len=14` and
  defaults `src` to the OHLC true-range inputs already resolved inside `atr()`
  (`TradeBuiltins.hx:491-508`), and relax/adjust `BuiltinSigs.hx:101` (`ind("atr")` minArgs) to
  accept the 1-arg form without breaking the existing 2-arg form.
- First step (do before coding): 15-minute repro — run a corpus file with `atr(13)` through the
  actual call path to confirm whether it currently throws a type error or produces NaN, since the
  registered `minArgs=2` (`BuiltinSigs.hx:630-632`) suggests it *should* be rejected at typecheck
  time in paths that run the checker.
- Effort: S–M. Independent of WP-A/B/D/E — can run **in parallel**.

**WP-D: Wire `count_true` into `prob_up` rendering (Finding #4)**
- Scope: replace the two throw sites (`Expand.hx:124`, `:157`) with a `count_true`-based
  rendering of `prob_up` (count of Monte-Carlo fan samples above a level, divided by K — matches
  the existing fan-reduction vocabulary documented in `musescript/evo/ProjSampler.hx:34` and
  `musescript/evo/SeriesNode.hx:9`).
- Effort: S. Lowest-risk package on the list — currently a hard throw, so there is no existing
  behavior to regress; this only *adds* a capability (evolution can now target `prob_up`).
- Independent — can run **in parallel** with everything. Good candidate to ship first/fastest
  since it's pure upside.

**WP-E: Repro + root-cause the interp-only multi-output cross-field quirk (Finding #5)**
- Scope: write a minimal repro (`donchian(20).mid` and `donchian(20).upper` both read in one
  expression, compared interp vs js vs wasm vs vm) to confirm/deny the `__scr` scratch-path theory
  at `MuseInterp.hx:852`, then fix if confirmed.
- Effort: S for repro, S–M for fix once root-caused.
- Independent, low priority — audit itself says this can wait until `candle(i).{…}` struct form
  is being promoted, so it need not be scheduled this cycle unless capacity is free.

**Sequencing:**
- **Parallel now:** WP-B (safety net, no decision needed), WP-D (pure unlock, no decision needed),
  WP-C-repro-step (find out the real atr failure mode).
- **Needs a human decision before code starts:** WP-A (min/max) — see below.
- **Low priority, schedule opportunistically:** WP-E.
- Nothing here has a hard cross-package dependency; they touch disjoint files (`TradeBuiltins.hx`
  regions differ, `Expand.hx` vs `HarnessContext.hx` vs `BuiltinSigs.hx`), so all five can be
  assigned to different people/agents simultaneously without merge conflicts, modulo WP-A's
  4-backend lockstep requirement (WP-A itself is sequenced internally: land all 4 backends in one
  PR, not incrementally, to avoid a parity-broken intermediate state).

**Decision needed from the human (WP-A2 only — WP-A1's kernel patch needs no decision):**
Fixing `min`/`max` changes the *actual numeric output* of every already-evolved genome and any
hand-written strategy that uses 2-scalar-arg `min`/`max` — because before the fix `min(a,b)` was
silently `a` always, and after the fix it becomes the true minimum. This means:
- Any banked fitness scores / leaderboard entries / champion genomes computed under the old
  semantics are now measuring a *different function* than what they'll compute post-fix.
- Golden/regression tests that assert exact numeric outputs and happen to exercise `min`/`max`
  will need re-baselining — confirmed list: `TestNmaEval.hx:116-119`, `TestNmaFitness.hx:84`,
  `TestSimplify.hx:177-180` (verify intent, may already be compatible).
- **Correction from the WP-A sub-agent that changes the framing**: the `NmaEval.hx:313-320`
  comment's premise — "fixing this would break cross-backend parity" — is **already false today**.
  WASM (`WasmEmitter.hx:403-406`, `StrategyWasmEmitter.hx:1383-1388`) and the evo-engine's own
  `Simplify.hx` constant-folder already do true min/max. So the status quo is not "consistent
  broken behavior," it's "3 backends (interp/JS/NMA — the ones that actually drive evolution and
  live scoring) disagree with 2 backends (WASM/Simplify) that are already correct." This weakens
  the case for leaving it as-is; the honest options are now:
  (a) fix interp/JS/NMA to match WASM/Simplify (restores TRUE parity, not just avoids breaking a
  parity that doesn't currently exist) and accept a repro-baseline refresh,
  (b) fix but gate behind a version/flag so old genomes keep old semantics and only new evolution
  runs get the corrected, now-actually-consistent palette, or
  (c) leave it — but this should be a conscious choice to *keep* a 3-vs-2 backend split, not a
  belief that it preserves consistency, since it currently doesn't.
- The human should also weigh in on whether WP-A1 (the standalone `volume_profile_v1.ms:51` kernel
  patch) should ship immediately regardless of the WP-A2 timeline, since it's a live bug with no
  parity/re-baseline entanglement.

---

## 4. Sub-agent findings (planning only, no code changes)

Two `general-purpose` sonnet sub-agents ran in the background, investigation/planning only
(explicitly instructed not to modify code), to deepen the two highest-value packages. Both have
completed; their findings are already folded into §2/§3 above. Summary of what each changed about
the plan:

- **Sub-agent 1 — WP-A (`min`/`max` fix + repro-baseline impact).** Key correction to the original
  audit: WASM (`WasmEmitter.hx:403-406`, `StrategyWasmEmitter.hx:1383-1388`) and the evo-engine's
  `Simplify.hx` constant-folder **already implement correct 2-arg min/max** — only interp
  (`TradeBuiltins.hx:277-282`), JS backend (`JsBackend.hx:1600-1601`), and NMA
  (`NmaEval.hx:321-325`) have the bug. So "fixing it would break parity" is backwards: parity is
  already broken (3 backends buggy vs. 2 correct), and the fix *restores* consistency rather than
  breaking it. Also surfaced a standalone live production bug — `kernels/volume_profile_v1.ms:51`
  — where the min-cap on an auction/volume-profile allocation is silently a no-op today,
  independent of the broader palette question (split out as WP-A1). Gave exact test/golden
  re-baseline list (`TestNmaEval.hx:116-119`, `TestNmaFitness.hx:84`, `TestSimplify.hx:177-180`)
  and corpus exposure (7 musegene corpus files + 1 hand-written test, ~13 occurrences). Confirmed
  this remains a **human decision**, but on sharper terms than the audit implied.
- **Sub-agent 2 — WP-B (`resetCrossState()` auto-reset design).** Confirmed every current
  production hot path (`Fitness.hx`, `GenomeStepper.hx`, `MuseRuntime.hx`, `MuseDebugSession.hx`)
  already resets correctly today, and no caller anywhere relies on cross-state surviving across
  repeated `runBacktest()` calls — so the proposed opt-out parameter is a pure safety margin with
  zero current consumers. Gave exact one-line edit points at `HarnessContext.hx:111` and `:141`,
  and explicitly verified (not just asserted) that double-reset is a no-op. **Confirmed: no human
  decision needed, safe to implement as-is.**

---

## 5. Recommended first move

**Start with WP-B (auto-reset `resetCrossState()` inside `runBacktest()`/`runPanelBacktest()`).**

Reasons:
1. It is the **only high-severity finding with zero decision dependency** — WP-A (min/max) is
   equally high-severity but is explicitly blocked on a human call about repro-baselining;
   WP-B has no such ambiguity based on what's confirmed in §1 (resetting is idempotent, existing
   correct callers are unaffected, only currently-unsafe *new* callers benefit).
2. It is the **smallest, most self-contained diff** (two methods in one file, `HarnessContext.hx`),
   with a clear opt-out escape hatch for any streaming use case that turns up.
3. It closes off an entire *class* of future bugs (every new integration point stops being a
   footgun) rather than fixing one instance, which is a better ROI than the narrower WP-C/WP-D/WP-E
   fixes.
4. It unblocks nothing else and blocks nothing else — pure parallelizable win, so starting it does
   not delay the WP-A decision or any other package.

Once the human has ruled on WP-A's re-baseline question, that package should be run next given its
severity — but it should not gate the start of WP-B, WP-C, or WP-D, all three of which can begin
immediately and in parallel with WP-A's planning/decision cycle.

---

## 6. Resolution log (2026-08-04) — ALL SHIPPED

Human ruled "go ahead with all the fixes" (incl. the WP-A re-baseline judgment call). Every
package is now applied, verified green, and committed (swept into `cdacffa`). Build=0; the only
two failing tests are Cursor-owned and unrelated (`TestTypes` missing `fs_read_bytes` sig/dispatch;
`TestWatAssembler` `unsupported value type i64`).

- **WP-A — min/max true 2-arg — DONE.** `TradeBuiltins` min/max now `haxe.Rest`, arity-aware
  (1-arg = iterable reduce; 2+ = element-wise). `JsBackend` switch cases made arity-aware.
  `NmaEval` case `"min"/"max"` now computes real `Math.min/max(a,b)` (comment updated). This
  **RESTORES parity** — WASM (`WasmEmitter.hx:403-406`) and `Simplify` already did true 2-arg;
  interp/JS/NMA were the outliers. `TestNmaEval` re-baselined to element-wise expectation
  `[10,11,11,11.5→11,13]`. **WP-A1 (kernel min/max) is subsumed** by the same fix.
- **WP-B — auto-reset — DONE.** `HarnessContext.autoResetCrossState:Bool = true` field (NOT a
  param — a param would break the `IHarness.runBacktest` interface signature). Both
  `runBacktest`/`runPanelBacktest` call `resetCrossState()` first when the flag is set. Opt-out
  preserved for streaming callers.
- **WP-C — `atr(n)` 1-arg — DONE.** `atr(harness, a, ?b)` treats 1-arg as implicit-OHLC window;
  `JsBackend` case + `BuiltinSigs` `fun("atr", [TSeries, TWindow], TSeries, 1)`. `atr(14)` now
  yields real trades (was silent NaN/0).
- **WP-D — prob_up renderable — DONE.** Both `Expand` throw-sites replaced: PSPoint →
  `count_true((base) > close)`; PSNoise K-fan → `count_true(z0>close, …, z_{K-1}>close) / K`.
  The evolution engine can now materialize prob_up nodes instead of aborting expansion.
- **WP-E — interp `donchian(n).mid` = null — FIXED (`71e66e3`).** Root cause was NOT a
  multi-output cross-field quirk: two `donchian` impls disagreed on the midline field name. The
  interp resolves `donchian` to `indicators/lib/Donchian.hx` (`.middle`); JS/WASM + `BuiltinSigs`
  + docs use `TradeBuiltins.donchian` (`.mid`). `.mid` read null under interp only, coerced to 0
  in a numeric compare, and fired a phantom trade. Both impls now carry BOTH `mid` and `middle`
  (equal); both sigs declare both; the WP-E assertion is restored + a `.middle==.mid` check added.

  *(superseded — original deferral note below)* — interp multi-output cross-field read — DEFERRED (documented).** Reading two fields of
  the SAME multi-output call in one interp expression (e.g. `donchian(n).mid` vs `.upper`) is a
  CONFIRMED interp-only bug. It is NOT the state-leak — it survives the WP-B auto-reset — and
  js/wasm/vm are all correct. Left as low-pri per this triage; `TestTier1Builtins` documents it
  in-place rather than asserting the broken path.
