# MuseScript

Embedded DSL for algorithmic trading workstations and strategy discovery.

Built on vendored [hscript](https://github.com/HaxeFoundation/hscript) **2.7.0**.

## Requirements

- Haxe **5.0.0-preview.1** (see `.haxerc`)
- Node.js (JS examples / tests)
- Python 3.10+ with local venv (Python examples / tests / numba / wasmtime)
- `haxelib install utest`
- `haxelib install hxnodejs`

## Setup

```powershell
haxelib dev musescript .
.\run.ps1 venv          # creates .venv + installs requirements.txt (numba, numpy, wasmtime)
```

## Quick start

```powershell
.\run.ps1 01            # MA crossover backtest (JS)
.\run.ps1 07            # runtime stress: JS+WASM and Python+numba+WASM
.\run.ps1 test          # utest on Node
.\run.ps1 test-py       # utest on Python (.venv)
.\run.ps1 all           # JS + Python examples and both test suites
```

Current test status (verified 2026-07-15): `node build/js/tests.js` **758/758**, `.venv python
build/py/tests.py` **737/737**, cross-runtime gate (example 07) **identical value across all 4
hosts (max delta 0)**.

## Examples

| # | Name | What it shows |
|---|------|----------------|
| 01 | hello-bar | `@strategy` / `@param` / `on bar` + SMA cross |
| 02 | params-tune | `@macro` + `tune` / `optimize` plan |
| 03 | discovery-pipeline | sample → pickBest → distill IR |
| 04 | order-flow | `match` over EventLog & EventStream (`MuseIter`) |
| 04b | order-flow-live | same via `MuseInterp.dispatchEvents` |
| 05 | generators | `yield` generators + TailCallPass |
| 06 | benchmark | JsEmitter compiled on-bar vs MuseInterp |
| 07 | runtime-stress | math-only `polySum`: pure-js / wasm / python / numba |
| 08 | indicator-suite | pure MuseScript `@indicator` on real OHLCV — **MuseInterp vs compile-js** (~4.5×) |
| 09 | indicator-kernels | SMA/EMA/RSI/ATR math kernel: js / wasm / python / numba |

Fetch real tape: `.\run.ps1 fetch-ohlcv` → `data/real/tape.csv`.

Example **09** is the fast path: same indicator *math* as 08 over float arrays (linear-memory WASM, numba). Example **08** exercises full `@indicator` / chart / MuseInterp semantics.

## Math-only compilation

Pure numeric `function` decls (no bars/orders/match/yield) can be emitted to:

| Target | Backend | Host |
|--------|---------|------|
| `js` | `JsMathBackend` | Node `eval` |
| `python` | `PyEmitter` | CPython |
| `numba` | `PyEmitter` + `@njit` | CPython + numba |
| `wasm` | `WasmEmitter` → WAT → wasm | Node WebAssembly / wasmtime |

```haxe
MuseScript.compileMath(src, "polySum", { target: "numba" }); // Array<Dynamic>->Dynamic
```

### Vectors, recent windows, and strings

The typed surface distinguishes numeric `Vector` values from relative Series lookback:

```muse
strategy WindowExample {
  onBar {
    closes = window(close, 21)       // oldest → current, up to 21 values
    priorClose = close[1]            // one bar before now
    firstBuffered = closes[0]        // ordinary vector indexing
    bars = ohlcv_window(8)           // row-major O,H,L,C,V; stride 5
    label = str_concat("muse", "script")
    when str_contains(label, "script"): long()
  }
}
```

Portable string functions are:

- basics: `str_len`, `str_slice`, `str_contains`, `str_concat`, `str_trim`
- ASCII case and tests: `str_lower`, `str_upper`, `str_starts_with`, `str_ends_with`,
  `str_index_of`
- literal composition: `str_replace`, `str_split`, `str_join`
- conversions: `str_to_float`, `str_to_bool`, `str_from_float`, `str_from_bool`

These are functions rather than reflective host string methods. `str_slice` and the optional
third argument of `str_index_of` accept negative indices relative to the end, then clamp the
starting position to the string bounds. `str_index_of` returns `-1` when no match exists.
`str_trim` removes only ASCII whitespace. `str_lower` and `str_upper` convert only ASCII A-Z/a-z
and preserve all other characters, avoiding locale and host Unicode-table differences.

`str_replace(source, needle, replacement)` is literal (never regex), replaces non-overlapping
matches left-to-right, and returns `source` unchanged when `needle` is empty. `str_split` is also
literal and preserves leading, interior, and trailing empty fields. With an empty separator it
returns one element per host string indexing unit; splitting the empty string this way returns
`[]`. `str_join` accepts the `StringArray` returned by `str_split`. Since MuseScript's `Vector`
type is numeric, string arrays are their own opaque type; indexing a `StringArray` returns
`String`.

`str_to_float` accepts only a trimmed decimal with optional sign, fraction, and exponent; invalid
input returns `NaN`. `str_to_bool` is true only for trimmed, ASCII-case-insensitive `true` or `1`
(all other input is false). Boolean output is exactly `true`/`false`; float output normalizes
zero, `NaN`, and infinities to `0`, `nan`, `inf`, and `-inf`.

String lengths, indices, slices, and empty-separator splits use the Haxe target's native string
indexing units. In particular, JavaScript counts UTF-16 code units while Python may count Unicode
code points. Portable strategies should treat non-ASCII text as opaque unless that distinction is
acceptable; no Unicode normalization or locale-sensitive case mapping is performed.

Interpreter and compiled-JS strategies support these vector/string operations. Python-hosted
strategy execution uses the interpreter path for them. Strategy WASM deliberately rejects them
and falls back because its current ABI exposes scalar OHLCV/feature reads, not guest-owned dynamic
vectors or strings. Math-only backends continue to accept host-fed array parameters independently.

### Statistics and scientific vectors

The dependency-free vector slice is available to interpreter, Python-hosted interpreter, and
compiled-JS strategies:

- `stat_mean`, `stat_median`, `stat_variance`, `stat_sample_variance`, `stat_stddev`,
  `stat_sample_stddev`, and bias-corrected Fisher-Pearson `stat_skewness`
- `stat_quantile(xs, p)` uses R-7 interpolation: `h = (n - 1) p`, linear between adjacent
  sorted values, with `p` restricted to `[0, 1]`
- `stat_covariance` is sample covariance (`n - 1`); `stat_correlation` is Pearson correlation;
  paired vectors must have equal length
- `stat_zscore` uses population standard deviation; `sci_cumsum`, `sci_diff`, and
  `sci_normalize` provide inclusive cumulative sums, first differences, and `[0, 1]` min-max
  normalization

Means/sums use compensated accumulation and variances/covariances use online centered updates.
Invalid or undersized scalar samples return `NaN`; empty vector transforms return `[]`; constant
z-score/normalization vectors return zeros. NaN/infinite elements follow IEEE-754 propagation.
These dynamic vector builtins share the vector/string backend limit above: strategy WASM does not
currently lower them when vectors are returned into opaque host objects. Scalar reducers over
`window(series, n)` compute on the series tape, and scalar `ml_*` / `stat_*` calls may also spill
direct array literals (including runtime scalar elements) or fixed-length `window(...)` operands
into a state-region scratch arena and reduce over `(ptr, len)`. Assigned scratch vectors are
first-class inside an `onBar` body as `(base, len)` locals, so
`xs = window(close, 3); stat_mean(xs)` and transforms such as `stat_zscore` / `sci_cumsum` /
`sci_diff` / `sci_normalize` / runtime `ml_softmax` (via host `exp`) stay on the WASM path, as does
scalar `ml_sigmoid`. Matrices, strings, and graph objects still fall back.

### Dependency-free ML builtins

Evolved strategies can use deterministic, pure `ml_*` globals:

- `ml_dot(a, b)`, `ml_sigmoid(x)`, and `ml_softmax(xs)`
- `ml_mse(actual, predicted)` and `ml_mae(actual, predicted)`
- `ml_linear_predict(features, weights, bias = 0)`
- `ml_ridge_fit(packedX, y, featureCount, lambda = 1e-6)`
- `ml_matrix(rows, cols, data)`, `ml_matrix_rows`, `ml_matrix_cols`, `ml_matrix_data`,
  `ml_matrix_get`, and `ml_ridge_fit_matrix(matrix, y, lambda = 1e-6)`

Matrices are JSON-safe `{rows, cols, data}` values with row-major numeric data and a typed
`Matrix` surface. Add a constant feature column when an intercept is needed. Fitting is bounded
to 32 features and 4096 rows, uses no external library, and returns `[]` for invalid dimensions,
non-finite data, or a singular solve. `ml_ridge_fit` remains available for packed vectors;
`ml_ridge_fit_matrix` derives the feature count from the matrix. Other vector operations return
`[]`, and scalar operations return `NaN`, for invalid inputs as appropriate.

The interpreter (including Python-hosted strategy execution) and compiled JS support the full
slice. Strategy WASM lowers scalar-returning ML/stat calls with compile-time numeric vector
literals such as `ml_dot([1, 2], [3, 4])` and `stat_mean([2, 4, 6])`, lowers the same family
when array elements are runtime scalars (spilled to scratch), and also lowers
`stat_mean` / `stat_variance` / `stat_stddev` / sample variants / `stat_covariance` /
`stat_correlation` / `ml_dot` / `ml_mse` / `ml_mae` / `ml_linear_predict` when arguments are
direct `window(series, n)` calls (fixed `n`) or mixtures of windows and array literals.
Assigned scratch `(ptr, len)` locals and the transforms above are supported; matrices, strings,
and graph objects still fall back. This does not change the independent math-only array ABI.

### In-memory graph runtime

MuseScript accepts a dependency-free, JSON-safe graph value:

```json
{
  "directed": true,
  "nodes": ["A", "B", "C"],
  "edges": [
    {"from": "A", "to": "B", "weight": 0.5, "relation": "supplies"},
    {"from": "B", "to": "C"}
  ]
}
```

`nodes` is the canonical ordering for neighbors, traversals, PageRank output, and shortest-path
tie breaks. Edges follow `directed`; undirected edges are traversable in both directions. Weight
defaults to 1 and must be finite and nonnegative. Node IDs are unique non-empty strings and edge
endpoints must already occur in `nodes`.

Available pure builtins are:

- `graph_neighbors(graph, node, direction = "out", maxResults = 256)`
- `graph_degree(graph, node, direction = "out")`
- `graph_has_edge(graph, from, to, relation?)`
- `graph_bfs(graph, start, maxDepth = 32, maxNodes = 1024)`
- `graph_reachable(graph, start, target, maxDepth = 32, maxNodes = 1024)`
- `graph_shortest_path(graph, start, target, weighted = false, maxNodes = 1024)`
- `graph_pagerank(graph, iterations = 20, damping = 0.85, maxNodes = 1024)`

The parser rejects malformed values, negative/non-finite weights, graphs above 4,096 nodes or
32,768 edges, traversal bounds above 4,096 nodes, and PageRank requests above 1,000 iterations.
Shortest path returns `{nodes, distance}` or `null`; PageRank stays in canonical node order.
The checker treats graph literals with `nodes` and `edges` as opaque `Graph` values. Neighbor
and BFS calls return `StringArray`, shortest paths return `GraphPath`, and PageRank returns
`GraphRanks`.

`GraphBuiltins.querySpecOptions` adapts the existing Kestrel `GraphQuerySpec` seed and bounds; it
does not define another query grammar and does not execute a live external knowledge graph.
Interpreter, Python-host interpreter, and compiled-JS dispatch support dynamic graph objects.
Strategy WASM explicitly refuses these calls and uses the normal host/interpreter fallback because
its scalar ABI cannot represent dynamic graph objects or path/rank results.

### Vendored Volume Profile kernel

`kernels/volume_profile_v1.ms` is the canonical conservative VPVR kernel used by the chart.
Regenerate the versioned browser artifact and manifest with:

```powershell
.\run.ps1 vpvr
```

The WASM export uses explicit mutable `f64` output memory; its complete v1 ABI and SHA-256 are in
`mobile/src/charting/indicators/musekernels/volume-profile-v1.manifest.json`. The mobile build only
consumes the generated artifact and never requires Haxe or Python at runtime.

## Layout

- `musescript.ast` — domain AST
- `musescript.parse` — MuseParser (hscript composition)
- `musescript.runtime` — CallFrame, MuseIter, Generator, PatternMatcher
- `musescript.interp` — MuseInterp
- `musescript.harness` — reference backtester + registries
- `musescript.plan` — MuseIR + MusePlanner
- `musescript.compile` — JS / Python / numba / WASM emitters + TailCallPass
- `musescript.checker` — series / match / generator checks
- `musescript.cli.GeneRunner` — headless fitness CLI (see MuseGene, below)
- `tools/` — `muse_math_runtime.py`, `wat2wasm_cli.py`
- `.venv/` — local Python env for tests / numba / wasmtime

## MuseGene — evolvable IR + GP harness

`../musegene/` (sibling package, pure Python, self-contained — see its own
[README](../musegene/README.md) and [design doc](../MUSEGENE_EVOLVABLE_IR.md)) is a typed,
frozen node algebra that expands into MuseScript source and evolves it with a minimal GP loop.
It talks to MuseScript over exactly one subprocess boundary — this repo's `GeneRunner` CLI, which
compiles a strategy and reports one JSON metrics line per genome:

```powershell
haxe build-cli.hxml            # -> build/js/gene-runner.js (build once; the harness auto-detects it)
cd ..; python -m musegene.demo --n 40 --symbol SPY
```

Verified (2026-07-14): `python -m musegene.tests.run_tests` **12/12** (including an end-to-end
validity gate — 90 random/mutated/crossed genomes parse+check clean via the real MuseScript
parser, not a stub); `python -m musegene.evolve --pop 40 --gens 8 --symbol SPY --min-trades 30`
takes a real SPY tape from Sharpe 0.634 → 0.807 over 8 generations under parsimony control.

## Public API

```haxe
MuseScript.run(src);                    // raw hscript.Expr
MuseScript.parse(src);                  // MuseProgram
MuseScript.plan(src);                   // ExecutionPlan
MuseScript.execute(src, harness);       // run with IHarness
MuseScript.compile(src, {target:"js", strict:true}); // BarStrategyFn; throws if emit fails
MuseScript.compileEx(src, {target:"wasm"}); // {fn, backend, emitted}
MuseScript.compileMath(src, name, {target:"numba"|"wasm"|"js"|"python"});
MuseScript.check(src);                  // warnings / errors
```

**Strategy compile:** `js` (cached eval) / `wasm` (HostABI `on_bar` — Node WebAssembly or Python wasmtime). `strict:true` refuses silent MuseInterp fallback. Optimize via `PlanRunner.bindCompiled(prog, feed)`.
