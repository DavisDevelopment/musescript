# VM performance trail

Per-checkpoint numbers for the Tier-A bytecode VM — captured at each feature rollout so we watch
**both** dials move: raw per-eval speed **and** evo champion quality (speed is worthless if the
strategies get worse). Re-run with `bash scripts/vm_bench_trail.sh "<label>"`.

**Read trends, not last digits.** The JVM interp is Graal-JITed (hard case); JS per-eval has JIT-warmup
noise (sma-cross has read 1.6–2.5× across runs); the evo run is multi-threaded and NOT bit-reproducible,
so champion OOS / PBO wobble run-to-run.

Columns:
- **JVM /eval** — warm per-eval speedup, `evaluateVm` vs interp-backed `evaluateCompiled`, NVDA IS 5161 bars.
- **JS /eval** — portable-tier per-eval speedup (no Graal JIT, no WASM): sma-cross / arith-heavy.
- **Champion** — from `pop=80 gens=20 seed=42 --vm`: name · best-elite OOS Sharpe · OOS hold-rate · seed-median GO/NO-GO · PBO.

| date (UTC) | sha | checkpoint | JVM /eval | JS /eval (sma / arith) | champion (OOS · hold · verdict · PBO) |
|---|---|---|---|---|---|
| 2026-07-31 | `2c9a0ec` | P0 baseline (V0–V6, `--vm`) | **1.05×** (15.9→15.2ms) | **1.6× / 1.88×** | fib_retr_100 · OOS 0.617 · hold 9/10 · **GO** · PBO 0.83 ⚠ |
