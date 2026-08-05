# WASM `muse.pd` eligibility (honesty)

Tabular DataFrame / PdSeries handles are **opaque objects** — not packed into
`VEC_SCRATCH`. After `MuseHostLower`, authors write `muse.pd.*` → flat `pd_*`.

Source of truth: `musescript/compile/WasmPdEligibility.hx` (+ opaque tagging in
`StrategyWasmEmitter.isOpaqueObjectType` for `TDataFrame` / `TPdSeries` /
`TIndex`). Twin of `docs/WASM_NP.md`.

## Caps

| Cap | Value | Meaning |
|-----|------:|---------|
| `MAX_VEC_LEN` | 64 | Max 1-D length for claimed-native `pd_rank1d` |

Over cap → **H** (`host_eval`), fail closed. Same scratch budget class as
`WasmNpEligibility.MAX_VEC_LEN`.

## Native subset (**N**)

| Op | Shape | Notes |
|----|-------|-------|
| `pd_rank1d` | 1-D ≤64 | Average-tie ascending rank → `$vec_rank`; literal `pct=true` → `$vec_rank_pct`. Const-fold via Haxe `GroupBy.rank1d`. Non-literal pct / descending / len>64 → **H** |

Do not invent silent native **frame** kernels. `pd_xs_rank` / `pd_resample` /
groupby / merge return opaque `TDataFrame` → still whole-module **U**. Authors
who already have packed score vectors should prefer `pd_rank1d` on WASM.

## Escape / unsupported (**H** / **U**)

| Tag | Meaning for `pd_*` |
|-----|--------------------|
| **H** | Per-statement `host_eval` for non-native forms of claimed ops, or future opaque round-trip |
| **U** | Practical WASM stance for builtins that **return** `TDataFrame`, `TPdSeries`, or `TIndex`: **whole-module fallback** (interp/JS), same honesty class as `TProbCloud` / `TBag` |

Documented catalog (representative of all frame `pd_*`): see
`WasmPdEligibility.HOST_ESCAPE` — construct/select, merge_asof/join, groupby,
pivot/melt, corr/cov, rolling/ewm, **resample**, grant CSV, `pd_xs_rank`, etc.
Unlisted `pd_*` is also escape / unsupported unless in `NATIVE_*`.

`pd_read_csv` / `pd_read_parquet` remain **U** on WASM fitness and **U** on
other engines unless `IoGrant` is attached (ingest tier).

## Engine matrix (M4+)

CI/local aggregator: [ENGINE_MATRIX.md](ENGINE_MATRIX.md)
(`bash tools/engine_matrix.sh` / `.\tools\engine_matrix.ps1`).

| Engine | Construct / select | merge_asof / join | groupby / pivot / corr | rolling / xs_rank / resample | `pd_rank1d` | Series `pd_series`/`pd_shift`/`pd_series_values` | read_csv / read_parquet |
|--------|--------------------|-------------------|------------------------|------------------------------|-------------|------------------|-------------------------|
| **Interp** | **N** (Haxe) | **N** | **N** | **N** | **N** | **N** | **U** unless grant |
| **JS** | **B** (`pd_*`) | **B** | **B** | **B** | **B** | **B** | grant / Studio (parquet: Node + hyparquet) |
| **Bytecode VM** | **U** (frames) | **U** | **U** | **U** | **H** ≤64 → OBJ `NdArrayF64` | **H** ≤64 → OBJ `Series`/`NdArrayF64` (`VmPdEligibility`) | **U** |
| **WASM** | **U** (opaque fallback) | **U** | **U** | **U** | **N** ≤64 | **U** (opaque Series) | **U** |
| **NMA** | Don't force frames into kind-switch | — | — | — | — | — | — |

## Evo palette `PD_*`

**Shipped (gated, default off):** `KPd("xs_rank", …)` via
`Variation.configureForPd` **and** `configureForUniverse` (or
`configureForPanel`, which sets the universe). Expand dual path:

| Universe width | Expand shape | WASM |
|----------------|--------------|------|
| `≤ MAX_VEC_LEN` (64) | `np_get_flat(pd_rank1d([score…], true), i)` | **N** (`$vec_rank_pct` + `np_get_flat`) when scores lower |
| `> 64` | one-row `pd_from_columns` + percentile `pd_xs_rank` cell extract | **U** (opaque frame) |

No open groupby/merge/HTTP. Coerces onto `PanelAction` / `target_weight` **or**
closed rank→bag templates (`PABagScanTop` /
`PABagRankWeights` → `portfolio_apply(bag_from_scan|bag_norm(bag_from_dict))`)
so selection scores via `Fitness.configurePanel` → `runPanelBacktest`. Closed bags
on WASM are HostABI hybrid: native score/`*_of` reads + `apply_bag_scan` /
`apply_bag_weights` (host `applyBag`) — **not** opaque whole-module fallback and
**not** per-statement `host_eval` when the Expand shape matches. Open
`bag_rank_mom` / `bag_computed` / `symbols()` / assigned bag locals remain **U**
(`PANEL_HOST_ESCAPE`).

Also gated: `KPd("shift", field, periods, …)` — size-capped Series lag
(`pd_shift(pd_series(window(field, w)), p)` → scalar). No universe required;
stays on the single-name fitness path (`hasKPd` true, `usesPanelFitness` false
unless a `PanelAction` is present). Frame `pd_shift` remains escape/U.

Enable trio:

```text
engine.configureForPanel(panel)
engine.configureForPd(null)       # or ["xs_rank"] / ["shift"] / both
# universe comes from panel; or configureForUniverse([...]) without panel growth-only
```

NMA columnarizes closed bag templates (`PABagScanTop` / `PABagRankWeights` →
score columns → equal bag or percentile xs_rank → `bag_norm` → `applyBag`);
`KPd("xs_rank")` / panel stay Expand→interp/JS (or WASM HostABI for closed bags).
Bytecode VM Series lane: packed `pd_rank1d` + gated Expand `pd_shift` chain are
**H** (`VmPdEligibility`, `len ≤ 64`) — `Fitness.evaluateVm` accepts `KPd("shift")`
and refuses `KPd("xs_rank")` / panel. `Fitness.preferVm` defaults ON
(Expand→interp fallback on U).

## Panel closed bags — native vs HostABI matrix

| Surface | Scores / `*_of` | Apply | Whole-module bail? |
|---------|-----------------|-------|--------------------|
| `buy` / `sell_all` / `target_weight` / `rebalance_equal([…])` | **N** | HostABI | No |
| `portfolio_apply(bag_from_scan({SYM:…}, k))` ≤64 | **N** (spill) | HostABI `apply_bag_scan` | No |
| `portfolio_apply(bag_norm(bag_from_dict({…})))` ≤64 | **N** (spill) | HostABI `apply_bag_weights` | No |
| `var b = bag_*…` / `bag_equal` / open `bag_rank_*` / `symbols()` | — | — | **U** (opaque) |
| Free-standing `bag_from_scan` / `bag_norm` (not inside HostABI apply) | — | — | **U** |

Tests: `TestPanelWasmParity` emit gates (`apply_bag_*`, no `host_eval`) + interp↔WASM parity.

## Follow-ups

- Bytecode VM: packed `pd_rank1d` + Series lane (`pd_series` / `pd_shift` /
  `pd_series_values`) OBJ-lane handles **shipped** (`VmPdEligibility`); deferred
  DataFrame/Index (`pd_from_columns`, groupby, merge, one-row `pd_xs_rank`,
  frame `pd_shift`) and Series ctor index/name / length/name scalars
- MultiIndex shipped: F64 and/or Str levels, N≥1 (`fromLevels` / groupby `as_index`
  takes all by-cols); `xs` / `xsStr` / `get_level_values(_str)` / `reset_index`.
- **String sidecar propagation (shipped):** `assignStr` / select / drop / slice /
  iloc / reset_index / xs; **concat** (axis 0/1); **join**; **merge_asof**; **melt**
  (Str idVars; Str-only valueVars → Str `variable`/`value`; **mixed F64+Str
  valueVars** → Str `variable`, F64 `value` (NaN on Str rows), Str `value_str`);
  **pivot** (Str `index`/`columns`, F64 `values`); **align/reindex**; window
  mapCols; **xs_rank** (F64 ranks; Str sidecars pass through); fillna (F64);
  dropna / isna (F64 NaN **and** Str `""` → missing; isna emits F64 0/1 masks
  for both); **corr/cov** skip Str; **resample** last-nonempty Str; CSV parse /
  Parquet `fromObjects` **and** Node/`fromColumnar` → Str sidecars for
  non-numeric columns (same cell policy as CSV).
  `Series` stays **F64-only** (no Series-of-strings) — use `tryGet` (null on
  Str/missing), `getStr` / `strValuesOf`, or `get_level_values_str`. Legacy
  `get(strCol)` still returns an empty Series.
- **codes / factorize (shipped):** `Factorize` F64/Str → codes+uniques; MultiIndex
  `.codes` / `.uniqueLevels` / `fromCodes` (codes-primary until densify); groupby
  partitions via int codes; flats `pd_factorize` / `pd_index_codes` /
  `pd_index_levels` / `pd_multi_index_codes`.
- **Still open / deferred:** Series-of-strings typed handle (not planned — stay
  on Str sidecar + `tryGet`/`getStr`); Arrow writer; open Dynamic melt `value`.
- Parquet ingest **shipped** (grant + optional `hyparquet` peer on Node; JVM → clear deny / CSV preconvert)
- Columnar NMA for PD-bearing `KPd` genomes (still Expand→interp / host_eval today)
- Deeper checker enforcement of `TDataFrame` ≠ `TSeries`
- Engine-matrix CI jobs beyond Node pd gate
- HostABI `bottom` scan / packed bag locals across statements (still U)
