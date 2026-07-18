# The story of MuseScript

Not a changelog. A changelog is `git log`. This is what the commits don't
say by themselves.

## Act 1 — arrival, not birth

MuseScript's first commit isn't a "hello world." On 2026-07-14 it landed as
**130 files, 20,232 lines** — a working tokenizer/parser (vendored hscript
2.7.0 underneath, lowered into a real MuseAST), a tree-walking interpreter,
a multi-backend compiler (JS, Python, WASM math kernels), a harness with
order simulation and event streams, a growing stdlib, and a README that
already promised JS *and* Python *and* WASM execution, `@strategy`/`@macro`
metaprogramming, and a discovery-pipeline example (`sample → pickBest →
distill`). It arrived with intent already built in, not discovered by
iterating on a blank file.

That matters for how you should read everything after it: this was never a
toy DSL that grew a compiler by accident. The compiler-shaped ambition was
there on day one. What came later was *filling in* that shape, not
discovering it.

## Act 2 — one day, twenty-six commits

The day after arrival (2026-07-15) is the densest stretch in the whole
history: 26 commits, one author, no breaks visible in the log. In order,
roughly:

- A **typed strategy surface** landed alongside the original untyped
  annotation dialect (`@strategy`/`@on` vs. `strategy Foo { onBar { ... } }`)
  — two front ends lowering to the same MuseAST, a decision that's still
  load-bearing today (`MuseParser.looksLike` dispatches between them).
- **WASM math kernels** grew from "lower a scalar stat" to "spill vectors
  into scratch memory" to "runtime softmax/sigmoid via host `exp`" in about
  four commits — each one a real capability, not a refactor.
- **KestrGraal** — a persistent GraalVM gRPC server holding one shared
  `Engine` and per-thread `Context`s — appeared as a from-scratch
  performance bet: "how fast can this actually go if we stop paying JVM
  startup cost per call."
- The **stdlib merged** stats, strings, ML, and graph builtins into one
  coherent typed surface in a single commit, with dynamic result containers
  typed properly rather than left as `Dynamic`.
- Bidirectional **AST↔JSON bridges** (`MuseAstJson`, `ExprJson` +
  `--extract-cond`) shipped the same day — "any valid computation is a
  legal tradelogic tree" was already the design principle, a year before it
  got written down as a comment.

Nothing here reads like exploration. It reads like someone executing a plan
they'd already fully formed, at a pace that only works when you're not
guessing.

## Act 3 — the bill comes due

2026-07-16's commit is the tell: **KestrGraal, built the day before, had
never been correctness-tested against anything beyond the single M0
reference strategy.** Batch-testing it against a wider set found `short()`'s
order type had never actually been implemented, and a missing `exp` import.
Measured throughput was real (~741k bars/sec single-call, ~4.6x under 8-way
concurrency) — but real speed on an untested code path is a liability, not
an asset, until someone checks. This is the first appearance of a pattern
that repeats for the rest of the project's life: **build fast, then find out
what you actually built.**

The next two commits ("arrow lambdas," "exactly, yessirree bob") are smaller
and later (2026-07-17) — a real language feature (fat-arrow lambdas
desugaring to the same `EFunction` node as `function(...)`) and what looks
like a benchmarking/tournament session (`build/bench_tourney.sh`,
`build/parity_after.txt`) whose artifacts made it into the commit but whose
narrative didn't make it into the message. Not every session gets written
down. That's fine — the code and the tests are the record that matters.

## Act 4 — the audit (2026-07-18)

This is the session that produced this file. It didn't start as an audit —
it started as "trade forex using stock fundamentals," a request specific
enough to sound like a joke and grounded enough to not be one (commodity
currencies really do correlate with the sector fundamentals of the
companies that produce the commodity). That work lived in a sibling
repo (`kalshai/`) and forced real rigor: point-in-time fundamentals only,
walk-forward validation, honest costs — and it came back **NO-GO**, reported
plainly, because the sign-of-earnings signal from a three-name basket
doesn't fire often enough to power a daily strategy. A clean negative result
is still a result.

That work surfaced a real bug in this repo along the way (a `sma("name", 1)`
workaround for a MuseScript resolver gap), which turned into the actual
question this file answers: *what else is sitting in this codebase as a
`TODO` nobody's gotten back to?*

The answer was a full sweep — every `TODO` in `musescript/`, triaged into
"fix now" and "real epic, needs its own plan" — and then working the epic
list top to bottom:

- **Native front end** (Stages A+B): a from-scratch tokenizer + parser
  mirroring the vendored hscript grammar exactly, gated behind a flag with
  counted fallback, proven identical via a 175-file golden-AST corpus before
  a single line of the flip (Stage C, deliberately *not* done yet — needs a
  soak period first) was written.
- **Execution realism**, first slice: a real pending-order book — limit,
  market, stop, TIF, slippage — wired through all three execution tiers via
  one entry point, with the empty-book case proven to be a true no-op (the
  whole existing suite passed *before* a single new test was added).
- **In-browser WASM tier**: a native WAT→binary assembler, cross-validated
  against `wasmtime`'s own assembler as an external oracle before being
  trusted anywhere near the runtime. That validation work is what surfaced
  two real, previously-invisible bugs in code that predates this session —
  `coerceF64` was a no-op, and `rising()`/`falling()`'s `minBars` argument
  was silently dropped in WASM — both invisible until something finally ran
  the WASM tier through a real validating engine instead of just emitting
  text and hoping.
- **Docstring introspection**: a genuine Haxe compile-time macro (not a
  script you have to remember to re-run) that extracts doc comments from
  builtin classes and merges them with the typed signature table at query
  time — deliberately un-gamed: internal helper methods with doc comments
  don't leak into the builtin surface just because they happen to be public.

Two items on the resulting roadmap were left alone on purpose: macro-
specialized numeric kernels (no profiling evidence they're needed — building
them speculatively would be exactly the KestrGraal mistake again, optimizing
before measuring) and a plugin capability sandbox (a security-boundary
decision, not a coding task — it needs a human to decide what a plugin is
allowed to touch before there's anything honest to build).

## What the pattern actually is

Read start to finish, this isn't a story about a DSL slowly acquiring
features. It's a story about the same failure mode recurring and the same
fix applying each time: **something gets built with real ambition and real
speed, ships without being run through anything that would actually catch
what's wrong with it, and later gets caught — not by luck, but because
someone eventually built the thing that could catch it.** KestrGraal's
untested `short()`. The WASM tier's silent type mismatch. The aux-column
identifier that resolved to `null → false` and quietly faked a zero-trade
backtest with no error at all.

None of those were caught by more code review. They were caught by building
an oracle — a cross-validator, a golden corpus, a parity suite — and making
the untested path run through it. The throughline of this repo, more than
any single feature, is that habit: don't trust what you haven't run, and
when you build something fast, build the thing that checks it next.

---

*For where this goes next, see [ROADMAP.md](ROADMAP.md) — six epics, three
done, two deliberately not started, one gate away from flipping the parser's
default front end.*
