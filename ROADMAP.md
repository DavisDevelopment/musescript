# MuseScript engine roadmap — the epics

Consolidated 2026-07-18 from TODOs previously strewn across the codebase.
Small/tractable TODOs were **done and removed** in the same pass (aux-column
identifier resolution + tests, feed-attach hax, MuseRuntime result envelope,
builtin hoisting/hardening, interpreter docs, stale-TODO audit). What remains
here is real multi-session work, each with a proposed shape and a gate.

## 1. Native front end (tokenizer + parser)

*Was:* `MuseScript.hx` header TODO.
Replace the vendored-hscript lexer/parser + MuseParser post-pass with an owned
tokenizer+parser: owned syntax decisions, first-class macro system, precise
spans/diagnostics, faster parse.

- ✅ **Stage A DONE (2026-07-18)**: golden corpus assembled — `corpus/parse/`
  (105 legacy-dialect sources extracted from inline tests + 12 musegene
  expansions) + `corpus/strategies/` + `examples/strategy-kinds/` (175 files),
  with `corpus/parse-golden/` AST-JSON snapshots and the
  `TestNativeParser.testCorpusParity` gate (MuseAstJson + raw-enum-dump
  equality, zero-fallback assertion).
- ✅ **Stage B DONE (2026-07-18)**: `musescript/parse/NativeParser.hx` — owned
  tokenizer + recursive-descent parser mirroring the vendored hscript grammar
  (same AST, same quirks), flag-gated behind `MuseParser.native` with COUNTED
  hscript fallback (`nativeFallbacks`; only XML markup and `#` preprocessor
  are unsupported). Full utest suite (1774+ assertions) green with the flag
  ON and OFF, zero fallbacks; musegene Python suite green with
  `MUSE_NATIVE_PARSER=1` end-to-end through GeneRunner.
- **Stage C (next)**: flip `MuseParser.native` default after a soak period of
  running suites/CI with `MUSE_NATIVE_PARSER=1`; keep the counted fallback one
  release, then delete `vendor/hscript`'s Parser dependency (Expr types stay
  until the AST is owned too) — retires the 4 vendor TODOs.
- Only after the flip: syntax growth (real macro system, better match, etc.),
  now against an owned grammar.

## 2. Execution realism (order book, slippage, latency, impact)

*Was:* `MuseRuntime.hx` header TODO + `OrderKind.hx` "flesh out" TODO.
Richer order semantics compose as **rules on the sim side**, not new AST verbs
(see `OrderKind.hx` doc).

- ✅ **First slice DONE (2026-07-18)**: `musescript/harness/OrderBook.hx` —
  pending limit/market/stop orders against `{ type, px, qty, tifBars }` specs
  on the existing verbs (`long({type:"limit",px:...})`), latency-honest (an
  order placed during bar t's handlers is never eligible before bar t+1),
  conservative gap-fill rules (gap-through fills at the better/worse OPEN,
  intrabar touch fills at the order's own px — see the class doc), TIF
  expiry, and `slippageBps` applied against the trader on top of the book's
  fill price. Wired through all three execution tiers (interp/JsBackend/the
  builtin closures) via one `OrderSim.submit` entry point; the legacy
  immediate-close-fill verbs never touch the book (empty book = bit-identical
  to pre-existing behavior — confirmed: the full suite passed unmodified the
  moment the wiring landed, before any new tests were added).
  `TestOrderBook.hx` (12 tests): fill-rule unit tests, slippage, legacy
  no-op parity, and interp↔js parity through the real language surface.
  `orders_pending()` / `orders_cancel_all()` builtins added; `slippageBps`
  exposed via `MuseRuntime.run` opts.
- ✅ **Groups + partial flat DONE (2026-08-03)**: `PendingOrder.groupId` +
  `onFill: "cancel_group"` — first fill cancels siblings (OCO / cancel-rest;
  same-bar: placement order wins). Immediate `flat({qty})` / `flat({frac})`
  scale-out via `OrderSim.submit` → `executeFlat`. Wired through interp,
  `muse.orders`, and JsBackend `api.long/short/flat` (all route `submit`).
  WASM keeps HostABI qty-only; object specs / partial flats / tags stay
  `host_eval`. Tests in `TestOrderBook` cover OCO stop→TP cancel, partial
  scale-out, and legacy empty-book parity.
- ✅ **Bracket sugar DONE (2026-08-03)**:
  `long|short({ qty, bracket: { stop:{px|dist}, limit:{px|dist}, link:"oco" } })`
  expands in `OrderSim.submit` to a pending entry plus OCO exit flats
  (shared `groupId` + `onFill:"cancel_group"` on stop/TP only). `dist` is
  resolved against place-time close (long: stop=ref−d / limit=ref+d; short
  mirrors). Same-bar protect: `OrderBook.evalBar` tracks running position so
  co-placed exits see the entry fill. WASM object specs stay `host_eval`.
- ✅ **Panel pending books DONE (2026-08-03)**: per-symbol `OrderBook` map on
  `PortfolioSim` (`bookOf` / `submit` / `beginBar` before panel handlers —
  same t+1 latency). Verbs: `portfolio_long|short|flat(sym, spec)` +
  `portfolio_orders_pending|cancel_all(?sym)`; `muse.portfolio.long/short/flat/
  pending/cancel_all`. Shared cash stays coherent; legacy `buy`/`rebalance_equal`
  immediate path unchanged. WASM pending/bracket object specs stay on
  `PANEL_HOST_ESCAPE` / `host_eval` (HostABI is qty-only).
- ✅ **Cross-symbol OCO + panel brackets DONE (2026-08-03)**: `groupId` is
  portfolio-global under `PortfolioSim` (`allocGroupId` / `observeGroupId`).
  `beginBar` fans out `onFill: "cancel_group"` to every symbol book after each
  fill (sorted symbol order → deterministic same-bar competition). Distinct
  groupIds keep independent multi-name OCOs isolated. Bracket sugar via
  `portfolio_long|short(..., { bracket: { stop, limit, link:"oco" } })` uses
  portfolio `allocGroupId` for exit legs. Tests in `TestPortfolioPanel`:
  cross-sym cancel-rest, per-sym independent groups, bracket expand+fill,
  interp surface, WASM `host_eval` for complex specs. Single-name `OrderSim`
  OCO unchanged (book-local).
- **Next**: market-impact models (pluggable fn of
  size/bar-volume/spread) layered on top of the same book once a real
  cost-calibration source exists — don't invent impact numbers speculatively
  (the turnover-cost-bug lesson: eval-side cost models must be validated
  against the fitting-side ones, not asserted).

## 3. Docstring introspection pipeline

*Was:* `BagBuiltins.hx` / `GraphBuiltins.hx` TODOs.

- ✅ **DONE (2026-07-18)**: `musescript/docs/BuiltinDocsMacro.hx` — a real
  Haxe `macro function` (not a codegen script — nothing to remember to
  re-run; the docs regenerate on every normal compile from the doc comments
  themselves, so they can't drift) that walks an explicit list of builtin
  classes at compile time, pulls each public static method's doc comment via
  `ClassField.doc`, and bakes the result into a plain array literal — zero
  runtime cost. `musescript/docs/BuiltinDocs.hx` merges that at query time
  with the always-current `BuiltinSigs` typed-signature table, filtered
  strictly to BuiltinSigs' own key set (`names()`) so internal helper
  methods that happen to have doc comments — `install`, `materialize` — can
  never leak into the builtin surface as if they were callable. Handles the
  one real naming-convention exception found (`pickBest` is registered in
  BuiltinSigs literally, no underscore, unlike every other hoisted static)
  by emitting both spellings and keeping whichever one actually matches.
  Exposed via `MuseScript.docs(name)` / `.docsList()` / `.docsMarkdown()`
  (the `docs("bag_set")`-from-the-IDE shape from this doc's original plan)
  and `gene-runner.js --docs-md` for CI-generated reference docs. 9 tests in
  `TestBuiltinDocs.hx`; current coverage is 18/~340 BuiltinSigs entries
  (the classes hoisted-with-docs so far: BagBuiltins, MacroBuiltins) —
  coverage is a metric here, not a gate; growing it means hoisting +
  documenting more builtin classes the same way, which needs no further
  pipeline work.
- Pairs with the in-app indicator-IDE direction (indicator `source` is
  already first-class there).

## 4. In-browser WASM tier

*Was:* `MuseRuntime.run` wasm-tier TODO.

- ✅ **DONE (2026-07-18)**: `musescript/compile/WatAssembler.hx` — a from-scratch
  WAT→binary encoder (s-expr parser + module/type/import/func/global/export/code
  section encoder) covering exactly the subset `StrategyWasmEmitter` /
  `StrategyWasmRuntimeWat` emit. No wabt.js, no subprocess — `tier: "wasm"` in
  `MuseRuntime.run` now assembles and runs natively in-process.
  Cross-validated during development against `wasmtime.wat2wasm` (external
  oracle) on 8 real corpus strategies: argument-exact host-call-sequence
  match over 40 driven bars (bytes legitimately differ — wasmtime's output
  carries a debug name section mine doesn't emit; both are valid, behaviorally
  identical modules). `TestWatAssembler.hx` (6 tests, in-suite, no external
  dependency) proves it end-to-end: assemble → instantiate via the JS engine's
  own native `WebAssembly.Module`/`Instance` → run → compare metrics bit-exact
  against the interp tier, across 4 real strategy shapes plus malformed-input
  rejection and a regression test for the bug below.
  Found and fixed TWO real, pre-existing, silent interp/wasm divergences while
  building this (the tier had never been run through a real validating engine
  before): `StrategyWasmEmitter.coerceF64` was a no-op passthrough — WASM
  comparison ops (`f64.lt` etc.) and `i32.and/or` always return `i32`, so any
  boolean-shaped expression assigned to a local silently produced an
  `i32`-into-`f64` type mismatch (`var ok = a > b;` — the `EVar`/`Assign`
  emission sites were calling raw `emitValue` instead of `coerceF64`, and
  `coerceF64` itself wasn't coercing anything); and `rising()`/`falling()`'s
  3-arg `minBars` form was silently dropped in the WASM emitter, causing real
  trade-count divergence vs interp/js on any strategy using it. Both fixed;
  the WAT-assembly work is what surfaced them.
- **Next**: wire the assembler into `StrategyWasmBackend.compile`'s Node path
  too (currently still shells to `tools/wat2wasm_cli.py` via wasmtime there;
  could unify on one assembler everywhere and drop that subprocess+Python
  dependency entirely). Panel WASM: literal-symbol
  `close_of`/`mom_of`/`sma_of`/`ema_of`/`rsi_of`/`sym_available`/`fund_of` on
  the feature tape (`field@SYM` from `PanelFeed`); HostABI
  `buy`/`sell_all`/`target_weight`/`rebalance_equal([...])`. Bags / scan /
  portfolio queries remain host_eval — see `PANEL_HOST_ESCAPE`,
  `TestPanelWasmParity`. Panel evo genomes: `SPanel` +
  `Variation.configureForUniverse` → Expand `*_of`; `PanelAction`
  (`PABuy`/`PARebalance`/`PATargetWeight`) → Expand HostABI
  buy/rebalance/target_weight (`TestPanelEvoGenomes`). Without a universe,
  Expand stays single-name `long`/`short`/`flat`. Bags/scan still escape.

## 5. Macro-specialized numeric kernels

*Was:* `StatsBuiltins.hx` header TODO.
Macro-generate Int/Float × Array/haxe.ds.Vector specializations of the stats
kernels. Do NOT start until a profile shows boxing/dispatch on a hot path —
current JS-target numbers (~1M bars/s js tier) suggest it isn't one.

## 6. Plugin/extension programs

*Was:* `MuseInterp.executeProgram` TODO.
General non-strategy programs already execute (decls + statements, no @on(bar)
→ value of last statement). "App plugin" support is a **capability surface**
question (what may a plugin touch: chart? storage? network? orders — surely
not), not an interpreter question. Design decided 2026-07-18: gate by
declared plugin *kind* (same pattern `BuiltinSigs.isPaletteOnly` already
uses) — always-allowed read-only compute (bars/series/params/stats/ML/graph
query), opt-in chart-kind (`plot`/`chart` commands), opt-in scanner-kind
(universe/panel reads, no order verbs); order verbs (`long`/`short`/`flat`/
`portfolio_*`) and anything not already in the language (network,
filesystem, raw Reflect/eval) stay out entirely.

**Status (2026-08-02):** engine capability table shipped —
`PluginKind` / `PluginCapabilities`, `MuseRuntime.checkWidget` /
`runWidget` / `pluginKinds()`, `MuseInterp.executePlugin`, docs in
`docs/PLUGIN_KINDS.md`, tests in `TestPluginKinds`. Kinds: `compute`
(default), `chart`, `panel`; `scanner` reserved (scan builtins still
denied). Mobile still has a host regex gate — switch to `runWidget` after
runtime rebuild + sync. No marketplace / scanner-kind consumer yet.

## 7. KestrGraal (Java/GraalVM WASM host) parity audit

*Was not a TODO* — a 2026-07-18 follow-up to the epics above, prompted by
STORY.md's own thesis: KestrGraal is the fastest execution path in the repo
(~741k-1.3M bars/sec) and had exactly ONE correctness check on record (a
single pinned SPY MA-cross number), which is exactly the pattern that let
KestrGraal's `short()` ship as a silent no-op for a day back in 2026-07-16.

Built a real parity harness (`test/test_kestrgraal.py::test_corpus_parity`,
+ `gene-runner.js --emit-wasm-file` to produce real assembled-via-WatAssembler
`.wasm` artifacts with no Python/wat2wasm dependency in the loop): 8 corpus
strategies + a synthetic minBars/`@on(position)` strategy, cross-validated
against the JS tier over 8419 real SPY bars via the live gRPC server.

**Found (again) exactly the predicted failure**: `MuseBacktestCore.makeEnv`
was missing `get_position`/`get_entry_price`/`get_bars_in_trade`/`get_cash`/
`get_equity`/`get_unrealized_pnl` — a gap the code's own comments already
documented as known but unfixed. `06_dual_ma_hard_stop` (the one corpus
strategy using `@on(position)`) failed outright with `"env does not contain
get_position"`, not a graceful degradation. Made strictly worse this session:
`rising()`/`falling()`'s 3-arg `minBars` form (fixed in the WASM emitter
earlier today) unconditionally needs `get_bars_in_trade` too, so that gap now
also broke a *2-arg-adjacent* feature that has nothing to do with position
hooks. Also found the Java build itself was stale (`target/` held
protobuf-generated classes inconsistent with the compiled server — `mvn
clean compile` was required before the server would even start).

**Fixed**: ported `OrderSim.hx`'s `entryBar`/`barsInTrade`/`equityAt`/
`unrealizedPnl` line-for-line into `MuseBacktestCore.OrderSim` (Java's
`OrderSim` had never tracked bar index at all), wired the six host imports.
All 9 parity cases pass bit-exact (trades/finalEquity/sharpe) against the JS
tier; the 3 pre-existing pinned-number tests still pass unmodified.

✅ **Closed the loop (2026-07-18, same day)**: `.\run.ps1 test-kestrgraal` now
starts the server, waits for readiness, runs the full parity suite, and
always tears the server down after — one command, no more "requires a
running server in another terminal" friction. Also caught (by actually
running the new target twice, not just writing it) a real process-tree leak:
`mvn` on Windows is a `.cmd` wrapper around a child `java.exe`, so
`Stop-Process` on the wrapper's PID left the JVM bound to the port;
`taskkill /F /T` (tree kill) was needed. There is still no CI in this repo
at all (everything is local-dev, `run.ps1`-driven) — this is the local
equivalent of a gate, not a CI job; revisit if/when CI gets added.

## 8. Pipeline discovery-process construct

*Was:* an unfinished Cursor session (2026-07-18) — a plan for a `pipeline`
language construct that "significantly expanded the language for actually
programming the process of identifying the strategy itself." No plan doc
was ever found on disk (checked both repos, no `.cursor` dirs, nothing
dated); it may never have been written down. What existed already: a
`pipeline`/`search { }` keyword in `StrategyParser.hx` that was pure sugar
for `@macro` (zero new capability), and `MusePlanner`/`PlanRunner`, which
already turn `sample`/`tune`/`optimize`/`pickBest`/`distill`/`ensemble`
call shapes inside a macro body into a real, executable `ExecutionPlan` —
but with a real, unaddressed gap matching this project's oldest, most
recurring lesson: `PlanRunner.optimizeStep` always searched and scored
against the SAME single feed. In-sample-only search, baked into the
language's own optimizer, with nothing stopping an overfit "best" from
being reported as if it meant something.

✅ **Designed fresh and built (2026-07-18)**: two new discovery-process
primitives, `walkforward(folds, ?embargo)` and `promote(fn)`, recognized by
`MusePlanner` as new `PlanStep` variants (`WalkForwardStep`,
`PromotionGateStep` — deliberately NOT a new `Decl` AST node, which would
have rippled through the ~18 files that exhaustively switch over `Decl`
for a change that's purely about the planning/discovery layer, never
compiled to JS/WASM). `PlanRunner.walkForwardOptimize` does the real work:
splits the bound feed into expanding-window train/test folds with an
embargo gap purged at each boundary (same discipline as OrderBook's
next-bar-only fills, applied to search instead of fills); each fold's
grid/coordinate search runs ONLY against train, and the winning params are
measured once against test — the search never sees its own scoring data.
`promote`'s predicate is evaluated exactly once, against the
folds-aggregate out-of-sample metrics, never any single fold and never the
in-sample numbers. A plan with no `walkforward()` step behaves exactly as
before (confirmed: `opt.walkForward == null`, `testNoWalkforwardStep...`
pins it) — zero risk to every existing optimize()/run() caller.

Found a real, pre-existing dialect gap while wiring `promote`'s lambda
argument: arrow lambdas (`(r) => ...`) only exist in the typed surface
(`StrategyParser`'s own expr grammar); the legacy `@macro`/`@strategy`
annotation dialect (vendored hscript) reserves `=>` exclusively for match
arms, so the identical predicate needs `function(r) return ...` there
instead — not a bug, but undocumented until this pass; now called out
explicitly in `TestWalkForwardPipeline.hx`'s class doc.

11 new tests (`TestWalkForwardPipeline.hx`): planner recognition, real
fold-splitting (expanding-window, correct counts), aggregate == mean of
fold OOS metrics (not a rederived approximation — checked against a
manually-computed mean), promotion gate pass AND fail cases, no-promote
leaves `promoted` null (not false — a search that never got a verdict
asked for is not the same as a search that failed one), legacy behavior
provably unchanged, honest NaN on insufficient data (no fabricated fold),
and the real `pipeline { }` typed-surface syntax end-to-end (not just the
`@macro` alias it lowers through).

**Next**: aggregate-across-folds uses the mean; worth a `promote` variant
gated on "N of M folds individually pass" (closer to PSR/DSR/PBO-style
robustness than a single averaged number can express) if a real search
turns out to need it — not built speculatively ahead of that need.

## 9. Wickra indicator port (single implementation, vectorized OR streamed)

*Was:* a user request to reverse-engineer/port Wickra's TA indicator set
(github.com/wickra-lib/wickra — 514 indicators, Rust core, streaming-first,
`Indicator` trait + a free `BatchExt` blanket impl for vectorized mode)
into MuseScript "such that they can be vectorized OR streamed, efficiently,
from a single implementation," explicitly authorizing engine changes.

Investigation first, before writing 514 indicators' worth of engine
plumbing: MuseScript's "interp" and "JS" tiers were already ONE shared
implementation (JsBackend compiles the same Haxe `TradeBuiltins.*`
functions the interp calls — not a separate hand-written JS layer), so the
real gap was narrower than it looked — one Haxe implementation plus a
hand-written WAT implementation for WASM, not three independent copies.
`IndicatorColumns`/`IndCol` already did real per-callsite incremental
caching for SOME indicators (`ema` grows its state genuinely O(1) per new
bar) but not others (`rsi`/`atr` rescan their whole trailing window from
scratch every call — O(len), not O(1) — and `rsi` isn't even Wilder-smoothed,
the standard definition). No batch/vectorized mode existed anywhere.

✅ **Mechanism built, scoped to interp+JS (2026-07-18)** — WASM deferred
per explicit direction, not attempted blind: `musescript/indicators/
MuseIndicator.hx` is a direct port of Wickra's `Indicator` trait
(`update`/`reset`/`warmupPeriod`/`isReady`/`name`, `Null<TOut>` instead of
`Option<TOut>` for warmup). `IndicatorBatch.hx` ports `BatchExt`'s blanket
impl — batch is free for every `MuseIndicator`, one `update()` loop, never
a second hand-written vectorized implementation to drift from the
streaming one. `BarIndicatorCache.hx` (new, on `HarnessContext`) gives
bar-input indicators the same "one live object per callsite, fed exactly
once per new bar" caching `IndicatorColumns` already did for series-input
ones — kept as a SEPARATE cache rather than retrofitted into `IndCol`,
because the input model genuinely differs (current Bar vs a resolved Float
series) and conflating them would have obscured both.

Five indicators ported as the proof slice — chosen to cover distinct
shapes (cumulative/O(1)-always, sliding-window, multi-output, Wilder-style
paired rolling sums): OBV, Williams %R, Aroon (`{up, down}`, matching the
existing `macd`/`bbands` multi-output convention), CCI, MFI. Each is a
line-for-line translation of wickra-core's Rust source, cited by path in
its own doc comment. New builtin names only (`obv`, `williams_r`, `aroon`,
`cci`, `mfi`) — deliberately did NOT touch the existing `rsi`/`atr`, whose
current (non-Wilder, non-incremental) behavior existing corpus strategies
and pinned parity tests (WASM tier, KestrGraal) depend on; migrating them
to Wilder-correct/incremental versions is a real, separate, deliberate
decision this pass flagged but did not make unilaterally.

18 new tests (`TestIndicatorPorts.hx`): known-value cases transcribed
directly from wickra-core's OWN Rust test fixtures (not re-derived —
checked against the same numbers upstream checks itself against, e.g.
MFI's `known_value_period_2` = 1200/23), `batch_equals_streaming` parity
for every indicator (Wickra's own naming for this exact property), and one
end-to-end interp<->compiled-JS parity test through the real language.
An unported-to-WASM call degrades honestly (`"strategy is outside the WASM
on_bar subset"`, the same message any other unsupported construct gets) —
confirmed live, not assumed.

✅ **Assembly line built (2026-07-18)** — the port is now the whole set, not a
slice, and the infrastructure makes that tractable + conflict-free. A
compile-time macro (`IndicatorRegistryMacro`) scans `musescript/indicators/
lib/` and collects every indicator's `spec()` into `IndicatorRegistry`;
`WickraBuiltins.install`, `BuiltinSigs`, AND `JsBackend` dispatch ALL derive
from that one registry — so adding an indicator is literally "drop one file
in lib/", zero shared-file edits, which is what lets the remaining ~440 be
ported in parallel with no merge conflicts. `IndicatorCache` unifies the
three input shapes (Candle→evalBar, f64→evalSeries, (f64,f64)→evalPair).
The 5 original ports were migrated into this pattern (transparent — suite
unchanged). Added: `Cmo` (series-input, proves evalSeries end-to-end), the
`prim/` primitives `Ema`+`Sma` (internal building blocks for composites,
NOT builtins — see below), and `testEveryRegisteredIndicatorIsCallable` —
a generic net that drives EVERY registered indicator through a real interp
backtest, so a mis-wired future port (bad dispatch / arg mishandling /
crash) fails for free with no per-indicator test needed.

Full inventory + recipe: `musescript/indicators/PORT_INVENTORY.txt` and
`PORTING.md`. The 514 break into: **442 Tier-1** (Candle/f64/(f64,f64)
input, no name collision → `lib/` builtins, portable now); **10 primitives**
(names that collide with existing MuseScript builtins — ema/sma/rsi/atr/
macd/wma/mom/roc/vwap/max_drawdown → `prim/`, internal, faithful Wickra
ports reused by composites, NOT re-exposed as builtins so existing behavior
+ parity tests are untouched); **63 Tier-3 deferred** (DerivativesTick/
CrossSection/Trade/OrderBook/TradeQuote input — need L2/tick/cross-section
data feeds the `Bar` model doesn't carry; a separate track).

**Next**: grind Tier-1 in batches under the recipe (translate one `.rs`
→ one `lib/*.hx` + spec() + fixture-transcribed tests). ~9/452 done. The
`rsi`/`atr` Wilder-correctness migration stays a separate decision (needs a
plan to re-pin every dependent parity test, not a silent change). Tier-3
needs the data feeds built first. WASM porting stays per-indicator, gated
on profiled hot-path need.
