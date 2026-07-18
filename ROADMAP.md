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
- **Next**: order-book support for panel/portfolio strategies (today
  single-symbol `OrderSim` only); market-impact models (pluggable fn of
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
  dependency entirely); panel/portfolio WASM support is still out of scope
  (same boundary as the JS tier today).

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
filesystem, raw Reflect/eval) stay out entirely — start with just the two
simplest kinds and only add scanner/order kinds if a real plugin author
hits the wall. Not yet built — no consumer exists yet (nothing in the app
loads/executes a "plugin" today), so building the capability table now would
be exactly the KestrGraal mistake below: infrastructure ahead of any real use.

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
