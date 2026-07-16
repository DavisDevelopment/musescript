# muse-graal-stress — MuseScript on GraalVM/GraalWasm (memory ABI)

Runs MuseScript strategy WASM with **exported linear memory** on GraalVM's WebAssembly
runtime. OHLCV history, indicators, and cross/rising/falling state live inside the module;
the host only supplies side effects (`get_param` / `long` / `short` / `flat` / chart décor).

## Dual ABI (same module)

| Mode | Host calls | Use when |
| --- | --- | --- |
| **Streaming** | `reset(capacity)` then `push_bar(o,h,l,c,v,t,i)` per bar | live / unknown length |
| **Preloaded** | pack OHLCV into `memory`, `configure_tape(bases…, len)`, then `on_bar(index)` | finite backtests / batch |

Both modes share:

- exported `memory` + `ensure_capacity(bytes)` (`memory.grow` inside WASM)
- internalized `sma/ema/rsi/atr/…`, `lookback_ohlcv`, static `crossover`/`crossunder`/`rising`/`falling` slots
- side-effect env imports only

## Prereqs

- GraalVM Community 25.1.3 on `PATH` (`JAVA_HOME` / `GRAALVM_HOME`)
- Maven 3.9.x
- muse-script venv (`.\run.ps1 venv`) for wat2wasm

## Run

From `muse-lab/muse-script`:

```powershell
.\run.ps1 graal
```

## Patterns for ecosystem Graal embeds

- Pin `org.graalvm.polyglot:polyglot` + `wasm-community` to the installed GraalVM version.
- Share one `Engine`, one `Context` per thread; `eval` → module, `newInstance(imports)` per task.
- Write OHLCV with Graal buffer APIs (`writeBufferDouble(LITTLE_ENDIAN, …)`); reacquire
  `exports.memory` after `ensure_capacity` / growth.
- Ship the emitter string table with the artifact (`on_bar.strings.json`) for params/labels.
- JDK 24+: `--sun-misc-unsafe-memory-access=allow` (Truffle / `sun.misc.Unsafe`).

## Baseline (2026-07-15, GraalVM CE 25.1.3, Win x64, memory ABI)

```
leg 1:  polySum n=2M — delta 0 vs pure Java
leg 2a: streaming   trades=277 equity=725994.1667410003 sharpe=0.5795 — delta 0 vs MuseInterp
leg 2b: preloaded   same — matches streaming + interp
leg 3:  streaming   ~16.7 ms/backtest (~505k bars/sec) on 8419 SPY bars
leg 4:  preloaded   ~12.1 ms/backtest (~694k bars/sec)
leg 5:  ~145 µs / newInstance
leg 6:  4 threads × 5 backtests, all identical to ground truth
GRAAL STRESS: PASS
```

Preloaded mode removes per-bar scalar push overhead and is the preferred path for offline
backtests; streaming remains the live ABI.

## KestrGraal — the bound persistent-process server (2026-07-15)

Grows this exact harness (`MuseBacktestCore.java`, extracted so both the stress test and the
server share it byte-for-byte) into a long-lived gRPC server instead of a one-shot `main()`:
one `Engine` for the process lifetime, one `Context` per worker thread, a per-thread module
cache keyed by `wasm_path` so repeated calls against the same artifact skip re-eval. Bound to
`127.0.0.1` only — desktop-local, never exposed on the network. Contract: `src/main/proto/
kestrgraal.proto` (`Ping`, `Backtest`).

```powershell
# start the server (port defaults to 51117; second arg is the muse-script root)
mvn -q -B exec:java -Dexec.mainClass=musescript.graal.KestrGraalServer -Dexec.args="51117 .."

# in another shell — unit + perf test (Python client, generated stubs)
cd ..
.venv/Scripts/python -m grpc_tools.protoc -I graal/src/main/proto `
  --python_out=graal/src/main/python --grpc_python_out=graal/src/main/python `
  graal/src/main/proto/kestrgraal.proto   # regenerate stubs (gitignored, not committed)
.venv/Scripts/python test/test_kestrgraal.py
```

Verified 2026-07-15: `Ping` + `Backtest` (streaming and preloaded) both match the known-good SPY
MA-cross result (trades=277, finalEquity=725994.1667410003, sharpe=0.5795298962243104) exactly —
same numbers the M0 gate and this file's own stress harness already established. First call after
a fresh module load: ~1.3s (module eval + JIT warmup). 50 subsequent warm calls: ~11.7ms/call
including full gRPC round-trip (~720k bars/sec on 8419-bar SPY, honestly counting network
overhead — the in-process baseline above has none). The warmup-once/reuse-many story is the
entire point: a per-request CLI spawn pays that 1.3s on every call, KestrGraal pays it once per
process lifetime.

**Not yet built:** streaming RPCs for continuous run-event progress (evolve/fit), `Evolve`/
`Fit` RPCs alongside `Backtest`, GraalVM Auxiliary Engine Caching (persist warmed ASTs across
process restarts, CE-compatible), PGO (Enterprise-only, licensing decision deferred). See the
merged execution plan's Phase 1 addendum for the full roadmap.
