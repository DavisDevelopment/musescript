# MuseScript NdArray dtypes

Concrete storage arms for the numpy-feel stack (`musescript.ndarray`).

## Default / fitness policy

**Default Muse path is always `float64` (`NdArrayF64`).**  
`muse.np.zeros`, `arange`, `asarray`, fitness tape bridges, and Sharpe/equity math
must not silently drop to float32. Narrower storage requires an **explicit**
`astype("float32"|"int32"|…)` or typed Haxe helpers (`Np.zerosF32`, `arangeI32`, …).

## Arms

| Dtype | Class | JS buffer | Else | Obtain via |
|-------|--------|-----------|------|------------|
| f64 | `NdArrayF64` | `Float64Array` | `Vector<Float>` | default factories |
| f32 | `NdArrayF32` | `Float32Array` | `Vector<Float>` + `truncF32` | `astype("float32")`, `zerosF32` |
| i32 | `NdArrayI32` | `Int32Array` | `Vector<Int>` | `astype("int32")`, `arangeI32` |
| bool | `NdArrayBool` | `Uint8Array` | `Vector<Int>` 0/1 | comparisons, `np.bool` |

`AnyNdArray` is a **cold** existential (`F64|F32|I32|Bool`) for Muse boxing only —
never for per-element kernel dispatch.

`NdArray<T>` `@:multiType`: `Float` → F64, `Int` → I32. F32 has no distinct Haxe
type; use the concrete class.

## `astype` / truncation

See `NdCast.hx` (source of truth):

| Cast | Rule |
|------|------|
| → f64 | widen copy |
| → f32 | IEEE754 binary32 round (`NdCast.truncF32`) |
| → i32 | toward-0 (`Std.int`) then **clamp** to int32 range (Muse-defined; safer than NumPy UB) |
| → bool | `v != 0 && v == v` (NaN → false) |
| bool → numeric | 0 / 1 |

Round-trips F64↔F32↔I32↔Bool are covered in `TestNdArray`.

Aliases: `"float32"`/`"f32"`, `"int32"`/`"i32"`/`"int"`, `"float64"`/`"f64"`/`"float"`, `"bool"`.

## Arithmetic promotion

| Operands | Result |
|----------|--------|
| F32 × F32 | F32 (`+ − * /`, matmul) |
| I32 × I32 | I32 integer arith (`+ − *`, matmul); **true divide → F64** |
| Mixed numeric | **F64** (fitness-safe) |
| `exp` / `log` / `sqrt` / `pow` | always **F64** via DetMath paths |
| Reductions `sum`/`mean` | Float accumulator (even for I32) |

Typed Haxe: `Np.addF32` / `mulI32` / …  
Existential: `Np.addAny` / `NdTypedOps.*Any` (used by `NpBuiltins` at the Dynamic wall).

## Muse surface

```text
muse.np.astype(a, "float32")   → NdArrayF32
muse.np.astype(a, "int32")     → NdArrayI32
muse.np.dtype(a)               → "f64"|"f32"|"i32"|"bool"
muse.np.add / multiply / …     → dtype-preserving when homogeneous
muse.np.take(a, i32_indices)   → F64 values; I32 index path (no F64 widen of indices)
```

### F64 promote boundary

F64-only kernels (axis/keepdims reductions, `where`, `compress`,
`assign_where`, fancy take on the *values* array after coerce, reshape, …)
go through **`NpBuiltins.requireNd`**: F32 / I32 / Bool → contiguous F64
copy, then the F64 kernel. Homogeneous F32/I32 arith and full reductions
(`sum`/`mean` without axis via `NdTypedOps.*Any`) stay typed.

Axis reductions that fully collapse to **0-d** with `keepdims=false` unwrap
to a host Float/Bool at the Muse builtins wall (NumPy-scalar feel) so
`muse.np.sum(xs, 0)` on 1-D compares like a number — matching WASM
`vec_sum` / `vec_mean`.

This is intentional honesty, not a silent dtype change on Muse
fitness paths (default Muse factories remain F64).

## Risk / sizing helpers

```text
muse.np.vol_target_qty(vol, target, base [, max [, min [, window [, eps]]]])
muse.np.mask_qty(mask, base [, max [, min]])
muse.np.rolling_log_vol(prices, window [, ddof])
```

- Default **f64**; log-returns use **DetMath** (fitness parity).
- Helpers return **requested** qty (scalar or NdArray) — they do **not** replace
  `OrderSim` cash / `riskCappedQty` (25% cash) clamps at fill.
- Anti-pattern: evolved `size = volume` is still sim-capped; prefer
  `vol_target_qty` / `mask_qty` for evo-safe sizing.
- WASM: documented **H** (`host_eval`) — see `docs/WASM_NP.md`.

## Gaps / next

- Typed F32/I32 axis reductions / where / compress (today: promote at `requireNd`)
- WASM ND linear memory views per dtype
- Optional F32 SIMD accel (never default fitness)
