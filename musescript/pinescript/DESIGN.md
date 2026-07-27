# musescript.pinescript — PineScript parser + PineScript→MuseScript transliterator

Import a TradingView Pine Script strategy/indicator, parse it into a faithful
Pine AST, then **lower that AST directly into `musescript.ast.*` nodes** so the
result is a first-class MuseScript program — not a shim, not interpreted-Python.
Once lowered it inherits every existing Muse backend (interp / JS / WASM /
native), the Studio debugger, universe-scale portfolio backtesting, and the
evolutionary optimizer.

> **Legal footing (checked 2026-07-25):** implementing a compatible parser +
> semantics from Pine's *published language docs* is standard interoperability
> work — squarely the *Google v. Oracle* (2021) fair-use case. Constraints we
> hold ourselves to:
> - Test corpus is **open-source / public-domain Pine only** (MPL-licensed
>   published scripts, self-authored scripts, or textbook indicator formulas).
>   Never scrape "protected"/invite-only scripts to reverse-engineer behavior —
>   TradingView's own house rules forbid that and so do we.
> - "Pine Script™" is a TradingView trademark. We *describe* compatibility
>   (nominative fair use); we never brand the product as affiliated/endorsed.
> - Comparative benchmark claims must be truthful + substantiated → the parity
>   harness (below) is what makes them defensible.

## Why AST→AST, never text→text

Piping through generated MuseScript *source text* throws away provenance and
doubles parse work. We lower Pine AST directly into `musescript.ast` (reusing
the same `MuseNodes` constructors `MuseParser` builds), then run the **existing**
`MusePrinter` to get human-readable `.hx` for review/diffing. One AST, two
consumers (compiler + printer) — the trick the codebase already uses internally.

## Package layout

```
pinescript/
  PineVersion.hx        # //@version=N sniff + version-gated feature flags
  lex/
    PineToken.hx        # token kind enum + Token record (span-carrying)
    PineLexer.hx        # indentation-significant tokenizer (INDENT/DEDENT/NEWLINE)
  ast/
    PineProgram.hx      # top-level: version, decls, spans
    PineDecl.hx         # indicator()/strategy()/library() header, fn defs, imports
    PineStmt.hx         # assignment, :=, if/for/while/switch, tuple-destructure
    PineExpr.hx         # exprs incl. history-ref e[n], ternary ?:, namespaced calls
    PineType.hx         # series/simple/const/input qualifier × base type lattice
  parse/
    PineParser.hx       # recursive-descent + Pratt expr parser, version-threaded
  semantics/
    SeriesTypeInfer.hx  # the real Pine type system: qualifier lattice + na propagation
    HistoryRef.hx       # [n] indexing / barstate / valuewhen resolution helpers
  translit/
    PineLower.hx        # Pine AST → Muse AST (the core transliteration pass)
    BuiltinMap.hx       # ta.* math.* strategy.* request.* plot* → Muse equivalents
    RepaintAudit.hx     # flags lookahead/security repaint patterns as diagnostics
    Unsupported.hx      # structured "can't translate this yet" report (never silent)
  cli/
    Pine2Muse.hx        # `pine2muse foo.pine -o foo.ms [--explain] [--audit]`
  tests/
    PineLexerTest.hx  PineParserTest.hx  PineLowerTest.hx
    corpus/             # license-clean .pine fixtures + golden Muse AST/output
```

Mirrors the existing `parse/ → ast/ → compile/` shape so it plugs into the same
utest harness and golden-corpus pattern (`corpus/parse-golden/`).

## The hard part: semantic mapping, not syntax

| Pine concept | Muse mapping |
|---|---|
| `series`/`simple`/`const`/`input` qualifiers | reconcile onto Muse series-vs-scalar (`SeriesLowering`, `SeriesLiveness` already exist) |
| `var`/`varip` persistent locals | Muse stateful builtin locals — *cleaner*, no intra-bar repaint distinction |
| `e[n]` history reference | `ELookback(series, n)` — Muse has this natively |
| `request.security()` other-tf/symbol | `PanelFeed`-backed multi-series join (universe scanner already exists) |
| `strategy.entry/exit/close`, pyramiding | Muse order model (`OrderKind`) + position-netting compat shim |
| `plot/plotshape/bgcolor/hline` | metadata-only in exec; optionally → glcharts annotations |
| `array.*`/`matrix.*`/`map.*` | Haxe-native; mostly a builtin-name remap |
| `import user/lib/ver` | no network fetch: inline known-lib source or flag unsupported-external |
| `na` value + propagation | `NaLattice`; Muse null semantics + explicit na-guards |
| lookahead / naive `security()` repaint | **`RepaintAudit` flags it, never silently ports the bug** |

## Multi-version

Grammar deltas v4→v6 are small (`study`→`indicator`, `security`→
`request.security`, tightened v5 type system, v6 additions). **One grammar with
version-gated productions**, not N parsers. `PineVersion` sniffs `//@version=N`
(default v5, TradingView's current default) and threads a flag through parse +
lowering so version-specific builtin renames resolve.

## Testing = numerical parity, not AST similarity

Golden corpus (license-clean scripts) → parse → lower → run **both** engines
over the same OHLCV tape → diff output series. Numerical parity is the trustworthy
bar. AST-diff goldens catch regressions cheaply; series-diff proves correctness.

## Marketing differentiators (all falsifiable, all real)

1. **No platform limits** — Pine caps exec time, `max_bars_back` (~500),
   loop iterations, `security()` count. Compiled WASM/native has none.
2. **Real portfolio/universe backtest** — Pine's tester is single-symbol.
   Muse has `runPanel` (320k cells/s) + portfolio order sim natively.
3. **Honest-exec by construction** — `fillNextOpen` + short-circuit parity;
   `RepaintAudit` turns Pine's famous silent repaint trap into a *feature*:
   "we import your strategy and tell you where it was lying to you."
4. **True multi-target compile** — offline, on-device, in-browser zero-backend,
   or inside an evolution loop. Not a proprietary cloud VM.
5. **Direct GP/distillation hook** — "paste your Pine strategy, we evolve it"
   → `strategy_lab` NSGA-II walk-forward / NMA substrate. No incumbent does this.
6. **No backtest/alert paywall** — local compilation removes the gate.
7. **Real debugging** — Studio breakpoints/stepping vs Pine's `plot()`/`log.info`.
8. **Speed as a live demo** — 720k–1.4M bars/s: literal side-by-side N× faster.

Launch "wow": import a popular open-source TradingView strategy → RepaintAudit
catches a real lookahead bug → auto-evolve a corrected variant in the browser.
Complete before/after in one artifact.

## Build phases

- **P0 — foundation (this slice):** version sniff, tokens, indentation lexer,
  Pine AST enums, typecheck hxml. Compiles clean, no lowering yet.
- **P1 — parser:** recursive-descent + Pratt expr; round-trips real indicator
  scripts to a Pine AST; lexer/parser golden tests.
- **P2 — lowering v0:** `PineLower` + `BuiltinMap` for the common indicator
  subset (`ta.*`, arithmetic, `plot`, `input.*`); emit Muse AST; printer golden.
- **P3 — strategy semantics:** `strategy.*` order model, position netting,
  `RepaintAudit`.
- **P4 — parity harness:** run both engines on shared tapes, series-diff gate.
- **P5 — long tail:** `request.security` multi-series, arrays/matrices/maps,
  library imports, switch/while, exotic builtins; `Unsupported` shrinks over time.
