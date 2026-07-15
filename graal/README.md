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
