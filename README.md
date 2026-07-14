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

## Layout

- `musescript.ast` — domain AST
- `musescript.parse` — MuseParser (hscript composition)
- `musescript.runtime` — CallFrame, MuseIter, Generator, PatternMatcher
- `musescript.interp` — MuseInterp
- `musescript.harness` — reference backtester + registries
- `musescript.plan` — MuseIR + MusePlanner
- `musescript.compile` — JS / Python / numba / WASM emitters + TailCallPass
- `musescript.checker` — series / match / generator checks
- `tools/` — `muse_math_runtime.py`, `wat2wasm_cli.py`
- `.venv/` — local Python env for tests / numba / wasmtime

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
