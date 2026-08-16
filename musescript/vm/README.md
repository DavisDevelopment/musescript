# MuseScript Tier-A bytecode VM

Portable stack VM (`musescript/vm/`) for the evo attribution-oracle hot path.
Design: `SPEC_BYTECODE_VM.md`. Execution checklist: `BYTECODE_VM_TODO.md`.

## Oracle enable

```
# CorpusEvoRun (JVM/Graal): preferVm is default ON; startup parity self-check aborts on mismatch.
# Opt out: … --no-vm
java … CorpusEvoRun …            # VM on (default)
java … CorpusEvoRun … --no-vm    # Expand→interp / NMA only

# Programmatic
Fitness.preferVm = true;   // default — evaluate() tries VM first; Expand→interp on VmUnsupported
Fitness.preferVm = false;  // opt out
```

`--no-vm` disables the oracle. With preferVm on, CorpusEvoRun aborts if gen-0 seeds are not
bit-identical trades/finalEquity vs interp. Escape hatches (always Expand→interp / NMA when armed):
- out-of-subset AST → `vm-unsupported` (deterministic whole-program boundary)
- panel genomes / host-projection refs → `vm-unsupported`
- Expand `KPd("xs_rank")` (panel / frame) → `vm-unsupported`
- gated `KPd("shift")` is Series-lane **H** (eligible when Expand shape fits caps)
- `Fitness.preferNma` still runs first when set; VM is next in the chain

**Regression soak** (still available): `.\tools\prefer_vm_soak.ps1` / `bash tools/prefer_vm_soak.sh`,
or `node tools/engine_matrix.mjs --soak`. Docs: `docs/ENGINE_MATRIX.md` § preferVm soak. Optional CI
job is `continue-on-error` / manual / weekly — not a required gate.

## Oracle-eligible (VM)

| Covered | Notes |
|---|---|
| `onBar` / `when` / `long`/`short`/`flat` | order ≤1 arg |
| locals, bar fields, arith/cmp/logic | `&&`/`\|\|` both sides (no short-circuit) |
| `if` / ternary | CMP_JZ fused |
| Prelude assigns + multiple onBars | before handlers each bar |
| `__cs` CROSS | crossover/crossunder/rising/falling |
| `CALL_BUILTIN` + `IND` static | 13 TB0 + slope/zscore_roll/percent_rank/ewm_*/hl2/hlc3/ohlc4/vwap |
| `__scr` SERIES | macd/bbands/stoch + EField |
| LOOKBACK | bar-field/`ident[n]` **and** call/expr lookback via `WITH_OFFSET` |
| **NP scalar B** | `np_mean` / `np_sum` / `np_dot` / `np_get_flat` → Float on nums |
| **NP handle H** | `window` → OBJ `Array<Float>`; cliff-2 `np_zeros`/`ones`/`full`/`asarray` (+ runtime elems) / pairwise / `cumsum`·`diff` / DetMath `exp`·`log` / `reshape` / `matmul`≤8 → OBJ `NdArrayF64` (`len ≤ 64`) |
| **PD handle H** | `pd_rank1d` → OBJ `NdArrayF64`; Series lane `pd_series` / Series `pd_shift` / `pd_get` → OBJ `Series`; `pd_series_values` → OBJ `NdArrayF64`; Frame lane `pd_from_columns` / `pd_xs_rank` / single-key groupby / `pd_join` / frame `pd_shift` → OBJ `DataFrame` (dims ≤64); cell extract via `np_get_flat` / `pd_nrows`·`pd_ncols` |

## Still tree-walk (Expand→interp)

arrays/objects/classes/match/loops/generators · multi-arg orders · method calls ·
user-`@indicator` `__cs` · locals shadowing bar fields · panel / host-projection genomes ·
opaque registry indicators stay `CALL_BUILTIN` (not `IND`) but still run on the VM ·
Index / merge_asof / keys-agg / transform·rank groupby / rolling·pivot·IO `pd_*` ·
Index-heap Series ctor index (`pd_index_range`, …) ·
other `np_*` (comparisons / risk helpers / axis·keepdims·ddof / multi-dim create / `len > 64` / matmul side >8)

## NP / PD eligibility (cliff 2 + 4 + PD)

Source: `VmNpEligibility` / `VmPdEligibility`.

| Tag | Engine | Ops |
|---|---|---|
| **B** | VM | `np_mean`/`np_sum`/`np_min`/`max`/`prod`/`std`/`var` (1-arg) · `np_size`/`ndim` · `np_dot` · `np_get_flat` · `pd_nrows`/`pd_ncols` · `pd_series_length`/`pd_series_name` |
| **H** | VM | `window` · `np_zeros`/`ones`/`full`/`asarray`/`array` · pairwise ±*/`minimum`/`maximum` · `cumsum`/`diff` · `exp`/`log` · `negative`/`abs`/`sqrt`/`square`/`sign` · `clip` · `reshape` · `matmul`≤8 · `pd_rank1d` · `pd_series` · `pd_shift` · `pd_series_values` · `pd_from_columns` · `pd_get` · `pd_xs_rank` · `pd_groupby_{mean,sum,std,agg}` · `pd_join` |
| **U** | VM | Index / merge_asof / keys-agg / transform·rank groupby · comparisons/risk `np_*` · axis/keepdims/ddof · over-cap / multi-dim create · matmul side >8 · descending `pd_rank1d` / `pd_xs_rank` arity-3 |

Closed evo: `KNp` and gated `KPd("shift")` may hit `--vm`; Expand `KPd("xs_rank")` still
`vm-unsupported` (panel honesty — do not force preferVm). Packed xs_rank ≤64 is columnar-NMA.
Hand-written packed `pd_rank1d` + gated frame shapes stay VM-eligible.

### Cliff-2 handle ABI (OBJ lane)

```
create:  np_zeros(n|[n]) | np_ones(...) | np_full([n], v) | np_asarray([const…|runtime scalars…]) | np_asarray(window(s,n))
ufunc:   np_add/sub/mul/div | np_minimum/maximum | np_cumsum/diff | np_exp/log (DetMath)
         | np_negative/abs/sqrt/square/sign | np_clip(…, const lo/hi)
         | np_reshape(…, const shape≤64) | np_matmul(…, sides≤8)
         → NdArrayF64 on OBJ (never nums)
use:     np_mean / np_sum / np_min / np_max / np_prod / np_std / np_var / np_size / np_ndim
         / np_get_flat / np_dot → Float on nums
cap:     len ≤ 64, contiguous 1-D (matmul sides ≤ 8); axis·keepdims·ddof stay **U**
```

WASM twin: packed `(i32 base, i32 len)` vector locals over `VEC_SCRATCH` (already native;
see `docs/WASM_NP.md` § Handle ABI). No second invent — same logical handle, different storage.

### Cliff-PD handle ABI (OBJ lane)

```
create:  pd_rank1d([const…], pct?) | pd_rank1d(window(s,n), pct?) | pd_rank1d(ND-handle, pct?)
         → NdArrayF64 on OBJ (never nums; never Index)
series:  pd_series([const…]|window|ND [, const index|name [, const name]]) → Series on OBJ
         pd_shift(series|frame-handle, const periods?) → same-kind handle on OBJ
         pd_get(frame, const col) → Series on OBJ
         pd_series_values(series-handle) → NdArrayF64 on OBJ
         pd_series_length(series) → Float; pd_series_name(series) → String
frame:   pd_from_columns({col: [const…]…}) → DataFrame (arity 1; nrows/ncols ≤64)
         pd_xs_rank(frame [, const pct]) → DataFrame (no descending 3rd arg)
         pd_groupby_{mean,sum,std}(frame, const by) | pd_groupby_agg(…, const fn?)
         pd_join(left, right, const on [, const how])  (no validate)
use:     np_get_flat / np_mean / np_sum / pd_nrows / pd_ncols / pd_series_length → Float on nums
         pd_series_name → String on OBJ
cap:     dims ≤ 64; pct const bool; periods const int `|p|≤64`; series ctor arity 1–3 (const index/name)
```

WASM twin for packed rank: `$vec_rank` / `$vec_rank_pct` on `VEC_SCRATCH` (`docs/WASM_PD.md`).
Series lane WASM twin: packed `(base,len)` + `$vec_shift` (`WasmPdEligibility`).
Frame lane remains **VM H only** (WASM frames still opaque **U**).

**Deferred:** Index heap handles; `pd_merge_asof`; groupby transform/rank/keys-agg;
`from_columns` index/columns arity; runtime (non-const) column objects.
Expand `KPd("xs_rank")` still Fitness-refused. `Fitness.preferVm` defaults ON.

## Parity gates

- `TestBytecodeVmParity` / `TestVmParityCorpus` — diverged==0
- `DetParityDump` — `-- MuseVm vs MuseInterp … match=1` + `-- MuseVm np_mean(window) … match=1`
  + `-- MuseVm np handle … match=1` + `-- MuseVm pd_rank1d handle … match=1`
  + `-- MuseVm pd_series/shift handle … match=1` + `-- MuseVm pd_frame handle … match=1`
- JVM preferVm startup `Fitness.vmParityCheck` (`--no-vm` opts out)
- **preferVm soak** (`TestPreferVmSoak` / `tools/prefer_vm_soak.*`) — Fitness-path bit-drift
  regression; default remains ON
