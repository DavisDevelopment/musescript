# VM performance trail

Per-checkpoint numbers for the Tier-A bytecode VM — captured at each feature rollout so we watch
**both** dials move: raw per-eval speed **and** evo champion quality (speed is worthless if the
strategies get worse). Re-run with `bash scripts/vm_bench_trail.sh "<label>"`.

**Read trends, not last digits.** The JVM interp is Graal-JITed (hard case); the evo run is
multi-threaded and NOT bit-reproducible, so champion OOS / PBO wobble run-to-run.

**Methodology note:** the P1a and P1b rows below used a single-run mean, which wandered ±15%
(Graal JIT + background load) and *swamped* the ~5–10% micro-opts — read those two rows as "parity
green, quality GO," not as reliable speed deltas. From `8261e21` on, the benches use
**min-of-interleaved-blocks** (stable: JS ±1%, JVM interp ±1.5%), so the `P1a+b (min-bench)` row is
the trustworthy cumulative number. Honest finding: on the real *indicator-heavy* workload the per-bar
cost is dominated by the builtin call (identical in interp and VM), so the Dynamic-stack VM's JVM
ceiling is ~1.2×; the portable tier sits ~1.6–1.9×. Bigger wins need Tier B (PE inlines the builtins).

Columns:
- **JVM /eval** — warm per-eval speedup, `evaluateVm` vs interp-backed `evaluateCompiled`, NVDA IS 5161 bars.
- **JS /eval** — portable-tier per-eval speedup (no Graal JIT, no WASM): sma-cross / arith-heavy.
- **Champion** — from `pop=80 gens=20 seed=42 --vm`: name · best-elite OOS Sharpe · OOS hold-rate · seed-median GO/NO-GO · PBO.

| date (UTC) | sha | checkpoint | JVM /eval | JS /eval (sma / arith) | champion (OOS · hold · verdict · PBO) |
|---|---|---|---|---|---|
| 2026-07-31 | `2c9a0ec` | P0 baseline (V0–V6, `--vm`) | **1.05×** (15.9→15.2ms) | **1.6× / 1.88×** | fib_retr_100 · OOS 0.617 · hold 9/10 · **GO** · PBO 0.83 ⚠ |
| 2026-07-31 | `74d4442` | P1a inline-cache builtins | 1.19x (17.05→14.275ms) | 1.65x / 1.65x | fib_retracement_100_breakout · OOS 0.6167 · hold 9/10 · GO · PBO 0.8333 |
| 2026-07-31 | `026f8f4` | P1b CMP_JZ superinstruction | 1.01x (18.2→18ms) | 1.46x / 2.01x | fib_retracement_100_breakout · OOS 0.6167 · hold 9/10 · GO · PBO 0.8333 |
| 2026-07-31 | `8261e21` | **P1a+b (min-bench, stable)** | **~1.2×** (15.0→12.5ms) | 1.62× / 1.88× | fib_retr_100 · OOS 0.617 · hold 9/10 · **GO** · PBO 0.83 |
| 2026-08-01 | (uncommitted) | **TB0 IND static dispatch** | **1.58×** sma (13.44→8.52ms) · control 1.31× ulcer (opaque) | 1.77× / 1.89× | fib_retr_100 · OOS 0.617 · hold 9/10 · **GO** · PBO 0.83 |

**TB0 note (2026-08-01):** the JVM row now reports TWO genomes via `--vm-bench-name`: `sma_8_cross`
(IND-lowered callsite — the TB0 path) and `ulcer_index_8_cross` (registry indicator, still opaque
`CALL_BUILTIN` — the control). TB0 broke the builtin ceiling *for the 13 lowerable TradeBuiltins
indicators* (sma/ema/rsi/atr/highest/lowest/stdev/wma/rma/roc/mom/change/pct_change): 1.2× → **1.58×**
where IND applies; the opaque-callsite ceiling (~1.3×) still stands for registry indicators. Next
lever if that residual matters: widen IND coverage to uniform-shape registry indicators, then Truffle.
