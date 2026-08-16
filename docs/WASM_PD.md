# WASM `muse.pd` eligibility (honesty)

Tabular **DataFrame / Index** handles are **opaque objects** — not packed into
`VEC_SCRATCH`. Eligible **Series** lowers to packed `(base,len)` (same scratch
class as muse.np). After `MuseHostLower`, authors write `muse.pd.*` → flat `pd_*`.

Source of truth: `musescript/compile/WasmPdEligibility.hx` (+ opaque tagging in
`StrategyWasmEmitter.isOpaqueObjectType` for `TDataFrame` / ineligible
`TPdSeries` / `TIndex`). Twin of `docs/WASM_NP.md`.

## Caps

| Cap | Value | Meaning |
|-----|------:|---------|
| `MAX_VEC_LEN` | 64 | Max 1-D length for claimed-native `pd_rank1d` / Series lane |

Over cap → **H** (`host_eval`), fail closed. Same scratch budget class as
`WasmNpEligibility.MAX_VEC_LEN`. Series `|periods| > 64` → **H**; index/name
ctor arity → whole-module **U**.

## Native subset (**N**)

| Op | Shape | Notes |
|----|-------|-------|
| `pd_rank1d` | 1-D ≤64 | Average-tie ascending rank → `$vec_rank`; literal `pct=true` → `$vec_rank_pct`. Const-fold via Haxe `GroupBy.rank1d`. Non-literal pct / descending / len>64 → **H** |
| `pd_series` | constvec / window / ND local ≤64 | Arity 1 only → packed `(base,len)` Series local. Index/name extras → **U** |
| `pd_shift` | Series handle + const periods | `$vec_shift` (FrameWindow.shift1d parity). Default periods=1; `|p|≤64`. Frame operand → **U** (WASM; VM may H) |
| `pd_series_values` | Series handle | Identity packed buffer for NP `np_get_flat` / `np_sum` / `np_mean` |

Do not invent silent native **frame** kernels. `pd_xs_rank` / `pd_resample` /
groupby / merge return opaque `TDataFrame` → still whole-module **U** on WASM.
Authors who already have packed score vectors should prefer `pd_rank1d` on WASM.

## Escape / unsupported (**H** / **U**)

| Tag | Meaning for `pd_*` |
|-----|--------------------|
| **H** | Per-statement `host_eval` for non-native forms of claimed ops (e.g. non-const `pd_shift` periods), or future opaque round-trip |
| **U** | Practical WASM stance for builtins that **return** `TDataFrame` or `TIndex`, and **ineligible** Series forms (index/name ctor, frame `pd_shift`): **whole-module fallback** (interp/JS), same honesty class as `TProbCloud` / `TBag`. Eligible Series lane is **N** — not U |

Documented catalog (representative of all frame `pd_*`): see
`WasmPdEligibility.HOST_ESCAPE` — construct/select, merge_asof/join, groupby,
pivot/melt, corr/cov, rolling/ewm, **resample**, grant CSV, `pd_xs_rank`, etc.
Unlisted `pd_*` is also escape / unsupported unless in `NATIVE_*`.

`pd_read_csv` / `pd_read_parquet` remain **U** on WASM fitness and **U** on
other engines unless `IoGrant` is attached (ingest tier).

## Engine matrix (M4+)

CI/local aggregator: [ENGINE_MATRIX.md](ENGINE_MATRIX.md)
(`bash tools/engine_matrix.sh` / `.\tools\engine_matrix.ps1`).

| Engine | Construct / select | merge_asof / join | groupby / pivot / corr | rolling / xs_rank / resample | `pd_rank1d` | Series `pd_series`/`pd_shift`/`values` (+ length) | read_csv / read_parquet |
|--------|--------------------|-------------------|------------------------|------------------------------|-------------|------------------|-------------------------|
| **Interp** | **N** (Haxe) | **N** | **N** | **N** | **N** | **N** | **U** unless grant |
| **JS** | **B** (`pd_*`) | **B** | **B** | **B** | **B** | **B** | grant / Studio (parquet: Node + hyparquet) |
| **Bytecode VM** | **H** gated `pd_from_columns`/`pd_get` (`VmPdEligibility`) | **U** asof · **H** `pd_join` | **H** mean/sum/std/agg · **U** pivot/corr | **U** rolling/resample · **H** `pd_xs_rank` (no desc) | **H** ≤64 → OBJ `NdArrayF64` | **H** ≤64 → OBJ `Series`/`NdArrayF64` + frame `pd_shift` | **U** |
| **WASM** | **U** (opaque fallback) | **U** | **U** | **U** | **N** ≤64 | **N** packed + `$vec_shift` + `pd_series_length`; name/ctor index **U** | **U** |
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
so selection scores via `Fitness.configurePanel` → `runPanelBacktest`. Gated bag
applies on WASM are HostABI hybrid: native score/`*_of` reads + `apply_bag_scan`
(±bottom) / `apply_bag_weights` / `apply_bag_raw` / `apply_bag_equal` /
`apply_bag_pair` (host `applyBag`) — **not** opaque whole-module fallback and
**not** per-statement `host_eval` when the gated shape matches. Assigned bag
locals / open `bag_rank_mom` / `bag_computed` / `symbols()` / free-standing
`bag_*` remain **U** (`PANEL_HOST_ESCAPE`).

Also gated: `KPd("shift", field, periods, …)` — size-capped Series lag
(`pd_shift(pd_series(window(field, w)), p)` → scalar). No universe required;
stays on the single-name fitness path (`hasKPd` true, `usesPanelFitness` false
unless a `PanelAction` is present). Frame `pd_shift` remains escape/U on WASM
(VM may H via Frame lane).

Enable trio:

```text
engine.configureForPanel(panel)
engine.configureForPd(null)       # or ["xs_rank"] / ["shift"] / both
# universe comes from panel; or configureForUniverse([...]) without panel growth-only
```

NMA columnarizes closed bag templates (`PABagScanTop` / `PABagRankWeights` →
score columns → equal bag or percentile xs_rank → `bag_norm` → `applyBag`) and
packed `KPd("xs_rank")` (`|universe| ≤ 64`, `field@SYM` scores → `pd_rank1d`).
Wide/frame xs_rank stays Expand→interp/JS. Bytecode VM Series + Frame lanes: packed `pd_rank1d` + gated Expand `pd_shift` chain +
const `pd_from_columns` / `pd_xs_rank` / single-key groupby / `pd_join` / frame `pd_shift`
are **H** (`VmPdEligibility`, dims ≤ 64) — `Fitness.evaluateVm` accepts `KPd("shift")`
and still refuses `KPd("xs_rank")` / panel (do not force preferVm). WASM Series lane is the
packed twin (`WasmPdEligibility`, `$vec_shift`). `Fitness.preferVm` defaults ON
(Expand→interp fallback on U).

## Panel closed / gated bags — native vs HostABI matrix

| Surface | Scores / `*_of` | Apply | Whole-module bail? |
|---------|-----------------|-------|--------------------|
| `buy` / `sell_all` / `target_weight` / `rebalance_equal([…])` | **N** | HostABI | No |
| `portfolio_apply(bag_from_scan({SYM:…}, k[, name][, bottom]))` ≤64 | **N** (spill) | HostABI `apply_bag_scan` (±bottom) | No |
| `portfolio_apply(bag_norm(bag_from_dict({…})))` ≤64 | **N** (spill) | HostABI `apply_bag_weights` | No |
| `portfolio_apply(bag_from_dict({…}))` ≤64 | **N** (spill) | HostABI `apply_bag_raw` | No |
| `portfolio_apply(bag_equal([…]))` ≤64 | — | HostABI `apply_bag_equal` | No |
| `portfolio_apply(bag_pair(L,S[,scale]))` literal | — | HostABI `apply_bag_pair` | No |
| `var b = bag_*…` / open `bag_rank_*` / `symbols()` / free-standing `bag_*` | — | — | **U** (opaque) |
| Free-standing `bag_from_scan` / `bag_norm` (not inside HostABI apply) | — | — | **U** |
| Nested bag algebra (`bag_add`/`bag_scale`/…), `portfolio_add\|sub\|mask` | — | — | **U** (DEFER) |
| Non-const scan `bottom` / dynamic sym lists / universe >64 | — | — | **U** (fail closed) |

Tests: `TestPanelWasmParity` emit gates (`apply_bag_*`, no `host_eval`) + interp↔WASM parity;
`TestPdM4` Series lane emit + interp↔WASM parity.

## Follow-ups

- Bytecode VM: packed `pd_rank1d` + Series lane (`pd_series` / `pd_shift` /
  `pd_series_values` / gated ctor index·name / `pd_series_length`·`name`) + gated
  Frame lane (`pd_from_columns` / `pd_get` / `pd_xs_rank` / single-key groupby /
  `pd_join` / frame `pd_shift` / `pd_nrows`·`ncols`) OBJ-lane handles **shipped**
  (`VmPdEligibility`); deferred Index / `pd_merge_asof` / keys-agg·transform·rank
  groupby / from_columns index·columns arity / runtime column objects.
  Expand `KPd("xs_rank")` remains Fitness-refused on evaluateVm.
- WASM: Series lane **N** shipped (`pd_series` / Series `pd_shift` /
  `pd_series_values` / `pd_series_length`); frames / Index / `pd_series_name` /
  Series ctor index·name stay **U** (packed scratch has no labels).
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
  `Series` stays **F64-only** (no Series-of-strings) — use host `muse.pd.try_get` /
  `get_str` / `str_values` / `has_str` / `assign_str` (Interp/JS **N**/**B**;
  VM/WASM **U** frames), or `get_level_values_str`. Legacy `get(strCol)` still
  returns an empty Series.
- **codes / factorize (shipped):** `Factorize` F64/Str → codes+uniques; MultiIndex
  `.codes` / `.uniqueLevels` / `fromCodes` (codes-primary until densify); groupby
  partitions via int codes; flats `pd_factorize` / `pd_index_codes` /
  `pd_index_levels` / `pd_multi_index_codes`.
- **Still open / deferred:** Series-of-strings typed handle (not planned — stay
  on Str sidecar + host flats); WASM `pd_series_name` / Series ctor index·name
  (packed scratch has no labels); Arrow writer; open Dynamic melt `value`;
  live EDGAR / fake impact models (never).
- Parquet ingest **shipped** (grant + optional `hyparquet` peer on Node; JVM → clear deny / CSV preconvert)
- Columnar NMA for PD-bearing `KPd` genomes (still Expand→interp / host_eval today)
- Deeper checker enforcement of `TDataFrame` ≠ `TSeries`
- Engine-matrix CI jobs beyond Node pd gate
- HostABI `bottom` scan / packed bag locals across statements (still U)
