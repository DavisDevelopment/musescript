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

Current test status (verified 2026-07-15): `node build/js/tests.js` **573/573**, `.venv python
build/py/tests.py` **555/555**, cross-runtime gate (example 07) **identical value across all 4
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

Portable string functions are `str_len`, `str_slice`, `str_contains`, `str_concat`, and
`str_to_float`. Negative `str_slice` indices are relative to the end and all bounds are clamped.

Interpreter and compiled-JS strategies support these vector/string operations. Python-hosted
strategy execution uses the interpreter path for them. Strategy WASM deliberately rejects them
and falls back because its current ABI exposes scalar OHLCV/feature reads, not guest-owned dynamic
vectors or strings. Math-only backends continue to accept host-fed array parameters independently.

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
