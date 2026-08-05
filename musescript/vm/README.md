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
| **NP handle H** | `window` → OBJ `Array<Float>`; cliff-2 `np_zeros` / `np_ones` / `np_asarray` → OBJ `NdArrayF64` (1-D, `len ≤ 64`, const shape/data) |
| **PD handle H** | `pd_rank1d` → OBJ `NdArrayF64`; Series lane `pd_series` / `pd_shift` → OBJ `Series`; `pd_series_values` → OBJ `NdArrayF64` (all `len ≤ 64`); cell extract via `np_get_flat` |

## Still tree-walk (Expand→interp)

arrays/objects/classes/match/loops/generators · multi-arg orders · method calls ·
user-`@indicator` `__cs` · locals shadowing bar fields · panel / host-projection genomes ·
opaque registry indicators stay `CALL_BUILTIN` (not `IND`) but still run on the VM ·
frame / Index `pd_*` (groupby, merge, `pd_xs_rank`, `pd_from_columns`, …) ·
Series extras (`pd_series_name` / `pd_series_length` / index·name ctor args) ·
other `np_*` (ufuncs, reshape, axis/keepdims, runtime-element asarray, `len > 64`)

## NP / PD eligibility (cliff 2 + 4 + PD)

Source: `VmNpEligibility` / `VmPdEligibility`.

| Tag | Engine | Ops |
|---|---|---|
| **B** | VM | `np_mean`/`np_sum` (1-arg) · `np_dot` · `np_get_flat` |
| **H** | VM | `window` · `np_zeros`/`np_ones`/`np_asarray`/`np_array` · `pd_rank1d` · `pd_series` · `pd_shift` (Series) · `pd_series_values` |
| **U** | VM | frame/Index `pd_*` · frame `pd_shift` · other `np_*` · axis/keepdims · over-cap / multi-dim create · descending `pd_rank1d` |

Closed evo: `KNp` and gated `KPd("shift")` may hit `--vm`; Expand `KPd("xs_rank")` still
`vm-unsupported` (panel / frame) — hand-written packed `pd_rank1d` pipelines stay eligible.

### Cliff-2 handle ABI (OBJ lane)

```
create:  np_zeros(n|[n]) | np_ones(...) | np_asarray([const…]) | np_asarray(window(s,n))
         → NdArrayF64 on OBJ (never nums)
use:     np_mean / np_sum / np_get_flat / np_dot → Float on nums
cap:     len ≤ 64, contiguous 1-D only
```

WASM twin: packed `(i32 base, i32 len)` vector locals over `VEC_SCRATCH` (already native;
see `docs/WASM_NP.md` § Handle ABI). No second invent — same logical handle, different storage.

### Cliff-PD handle ABI (OBJ lane)

```
create:  pd_rank1d([const…], pct?) | pd_rank1d(window(s,n), pct?) | pd_rank1d(ND-handle, pct?)
         → NdArrayF64 on OBJ (never nums; never AnyDataFrame)
series:  pd_series([const…]|window|ND) → Series on OBJ
         pd_shift(series-handle, const periods?) → Series on OBJ  (frame form → U)
         pd_series_values(series-handle) → NdArrayF64 on OBJ
use:     np_get_flat / np_mean / np_sum → Float on nums
cap:     len ≤ 64; pct const bool; periods const int `|p|≤64`; series ctor arity 1 (no index/name)
```

WASM twin for packed rank: `$vec_rank` / `$vec_rank_pct` on `VEC_SCRATCH` (`docs/WASM_PD.md`).
Series lane is **VM H only** today (WASM Series still opaque **U**).

**Deferred:** `AnyDataFrame` / Index heap handles (`pd_from_columns`, groupby, merge,
one-row `pd_xs_rank`, frame `pd_shift`); Series ctor index/name; `pd_series_length` / name.
`Fitness.preferVm` defaults ON (Expand→interp on U).

## Parity gates

- `TestBytecodeVmParity` / `TestVmParityCorpus` — diverged==0
- `DetParityDump` — `-- MuseVm vs MuseInterp … match=1` + `-- MuseVm np_mean(window) … match=1`
  + `-- MuseVm np handle … match=1` + `-- MuseVm pd_rank1d handle … match=1`
  + `-- MuseVm pd_series/shift handle … match=1`
- JVM preferVm startup `Fitness.vmParityCheck` (`--no-vm` opts out)
- **preferVm soak** (`TestPreferVmSoak` / `tools/prefer_vm_soak.*`) — Fitness-path bit-drift
  regression; default remains ON
