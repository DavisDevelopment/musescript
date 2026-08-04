# WASM `muse.np` eligibility (honesty)

Packed contiguous **f64** in `VEC_SCRATCH` — not a silent BLAS. After
`MuseHostLower`, authors write `muse.np.*` → flat `np_*`.

Source of truth: `musescript/compile/WasmNpEligibility.hx` (+ emit in
`StrategyWasmEmitter` / kernels in `StrategyWasmRuntimeWat`).

## Caps

| Cap | Value | Meaning |
|-----|------:|---------|
| `MAX_VEC_LEN` | 64 | Max 1-D length for claimed-native ops |
| `MAX_MATMUL_SIDE` | 8 | Max side for each of m, n, p in `np_matmul` |

Over cap → **H** (`host_eval`), fail closed.

## Native subset (**N**)

| Op | Shape | Notes |
|----|-------|-------|
| `np_dot` | 1-D × 1-D | → `$vec_dot` (same path as `ml_dot`) |
| `np_mean` / `np_sum` | 1-D | bare, or literal `axis` ∈ `{0,-1}` with `keepdims` absent/false → `$vec_mean` / `$vec_sum`; windows ok if `len ≤ 64`. Other axis / `keepdims=true` → **H** |
| `np_asarray` / `np_array` | 1-D literal / window / vec local | shaped/`asarray(x, shape)` → **H** |
| `np_zeros` / `np_ones` / `np_full` | literal shape `[n]` only | multi-dim → **H** |
| `np_add` / `subtract` / `multiply` / `divide` | same-length 1-D only | no general broadcast → **H** |
| `np_cumsum` / `np_diff` | 1-D | → `$vec_cumsum` / `$vec_diff` |
| `np_exp` / `np_log` | 1-D | → `$vec_exp` / `$vec_log` via **DetMath** (`$det_exp` / `$det_log`); const-fold at emit uses Haxe `DetMath` |
| `np_matmul` | packed row-major array-decl matrices | sides ≤ 8; result flat `m*p` in scratch; `$nd_matmul` or const-fold |

Operands: array literals, `window(series, n)`, vector locals from native vec
assigns, and nests of the above.

Native scratch operands are always **1-D**, so `axis=0` / `axis=-1` on
`sum`/`mean` is the full reduction (NumPy-correct for 1-D). Host Muse
unwraps 0-d results to Float (`NpBuiltins.maybeScalarNd`) so parity holds.
True multi-axis / ND axis reduce still needs shape metadata → **H**.

## Escape list (**H**)

Per-statement `host_eval` (F1). Does **not** force whole-module fallback
(`TNdArray` is not opaque). Documented set: `WasmNpEligibility.HOST_ESCAPE`
/ `StrategyWasmEmitter.NP_HOST_ESCAPE` — includes reshape/transpose, non-trivial
axis reductions, comparisons, fancy index, `outer`, `arange`/`eye`, etc.

Unlisted `np_*` not in the native tables is also **H**.

Risk / sizing helpers (`np_vol_target_qty`, `np_mask_qty`, `np_rolling_log_vol`) are
documented **H** — rolling DetMath log-vol and clamps are host-side; they return
**requested** qty arrays/scalars only. `OrderSim.riskCappedQty` / cash still clamp
at fill (`size = volume` anti-pattern remains sim-capped).

Host import `env.exp` remains **libm** `Math.exp` for `ml_softmax` /
`ml_sigmoid` only — **not** used by `np_exp`/`np_log`.

## Panel / aux

Unchanged: feature tape `field@SYM`, `PANEL_HOST_ESCAPE`, HostABI qty-only
`buy` / `sell_all` / literal `rebalance_equal`. Pending-book verbs
(`portfolio_long|short|flat`, brackets, OCO/object specs — including
cross-symbol `groupId`) are **H** (`host_eval`); see ROADMAP “Cross-symbol
OCO + panel brackets”.

## Follow-ups

- SIMD `f64x2` / `v128` for `vec_*` / `nd_matmul` (skipped unless easy win)
- True ND axis-0 reduce once shape metadata lives in the frame
- Optional evo `NP_MATMUL` / mask qty once Expand+size-cap tests exist (mean/dot/sum gated via `Variation.configureForNp`)
