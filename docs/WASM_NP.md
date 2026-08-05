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

| `np_get_flat` | packed 1-D + **const** index | → `f64.load` at `base+8*i`; non-const index / unbound maxLen / `i ≥ maxLen` → **H**. Enables Expand `pd_rank1d` cell extract. |

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



## Handle ABI (cliff 2)



Logical handle = contiguous 1-D F64 buffer + length. Two engine encodings:



| Engine | Storage | Create | Consume |

|--------|---------|--------|---------|

| **WASM** | Packed `(i32 base, i32 len)` locals → `VEC_SCRATCH` | `np_zeros`/`ones`/`asarray` bind vector locals | `$vec_mean` / `$vec_sum` / `f64.load` get_flat |

| **Bytecode VM** | OBJ-lane `NdArrayF64` (`VmNpEligibility.HEAP_ND`) | same ops via `CALL_BUILTIN` (const shape/data, `len ≤ 64`) | `np_mean`/`sum`/`get_flat`/`dot` → Float on **nums** |



Nums lane stays unboxed Float — no Dynamic matrices on the numeric stack.

WASM already ships the packed vertical; VM cliff-2 adds the OBJ-lane twin so

short ND pipelines do not Expand→interp solely for create+reduce.



**Deferred (WASM):** DataFrame / `TPdSeries` / Index handles — stay **H** / opaque **U**.
Bytecode VM ships Series-lane **H** (`pd_series` / `pd_shift` / `pd_series_values`) plus
packed `pd_rank1d` (**N** on WASM, OBJ **H** on VM); frames/Index stay VM **U**.
See `docs/WASM_PD.md`.



## Engine matrix (NP)

CI/local aggregator that rebuilds these claims: [ENGINE_MATRIX.md](ENGINE_MATRIX.md)
(`bash tools/engine_matrix.sh` / `.\tools\engine_matrix.ps1`).

| Engine | Scalar mean/sum/dot of window | Vec create + mean/sum/get_flat | Axis+keepdims / reshape |

|--------|-------------------------------|--------------------------------|-------------------------|

| **Interp** | **N** | **N** | **N** |

| **JS** | **B** (`np_*`) | **B** | **B** |

| **Bytecode VM** | **B** (`VmNpEligibility`) | **H** create + **B** reduce (cliff 2; const 1-D ≤64) | **U** |

| **WASM** | **N** (≤64) | **N** packed `(base,len)` | **H** |

| **NMA** | `nma-unsupported` (Expand→interp) | — | — |



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

- VM: runtime-element `asarray([close, …])` (WASM already); optional packed-header mirror


