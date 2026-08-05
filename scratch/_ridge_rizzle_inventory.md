# Deferred-ridge inventory (pd / np / vm / wasm / evo)

**Status:** living checklist — audit only (2026-08-05).  
**Doctrine:** fail closed N/B/H/U; never silent BLAS.  
**Sources of truth:** `docs/WASM_PD.md`, `docs/WASM_NP.md`, `docs/ENGINE_MATRIX.md`,  
`WasmPdEligibility` / `WasmNpEligibility` / `VmPdEligibility` / `VmNpEligibility`,  
`Fitness.evaluateVm` / `evaluateNma`, `Expand.pdExpr`, `PANEL_HOST_ESCAPE`.

**Cliff owners (parallel workstreams):**

| Cliff | Owns |
|-------|------|
| **frames** | DataFrame / Index / frame `pd_*` on WASM+VM; `KPd("xs_rank")` panel/frame U; wide `|universe|>64` Expand path |
| **wasm-series** | WASM `TPdSeries` opaque U twin of VM Series H (`pd_series` / `pd_shift` / `pd_series_values`) |
| **series-meta** | Series ctor index/name; `pd_series_name` / `pd_series_length`; frame `pd_shift` |
| **nma** | Columnar PD/KPd; residual panel opens; sim-coupled / KFeature; NP beyond closed window mean/sum/dot |
| **open-bags** | `bag_rank_*` / `symbols()` / assigned bag locals / bottom scan / free-standing `bag_*` |
| **wasm-np** | Residual `HOST_ESCAPE` NP; over-cap; axis/keepdims; matmul sides; risk helpers |
| **vm-np** | VM `UNSUPPORTED` NP; runtime-element asarray; reshape; ufuncs |
| **series-meta / ingest** | Grant IO, Arrow writer, Series-of-strings (product never) |
| **evo-palette** | Optional `NP_MATMUL` / further `PD_*` growth; Expand dual path honesty |

Legend: **N** native · **B** builtin · **H** host_eval / OBJ handle · **U** unsupported / whole-module fallback.

---

## 1. Already shipped (do not re-audit as holes)

| Surface | Where | Notes |
|---------|-------|-------|
| WASM `pd_rank1d` ≤64 | `WasmPdEligibility.NATIVE_VEC`, `$vec_rank(_pct)` | **N** |
| Expand dual xs_rank ≤64 | `Expand.pdXsRankExpr` → `np_get_flat(pd_rank1d…)` | Hits WASM **N** |
| VM packed `pd_rank1d` + Series lane | `VmPdEligibility.HEAP_PD` | **H** OBJ |
| VM cliff-2 ND create+reduce | `VmNpEligibility` | **H**+**B** |
| WASM NP packed subset | `WasmNpEligibility.NATIVE_*` | **N** (caps) |
| Closed bags HostABI | `apply_bag_scan` / `apply_bag_weights` | Hybrid, not opaque bail |
| NMA closed panel + bag templates | `PABuy`/`PARebalance`/`PATargetWeight`/`PABagScanTop`/`PABagRankWeights` | backend `nma` |
| `Fitness.preferVm` default ON | Expand→interp on U | soak optional CI |
| MultiIndex / factorize / Str sidecar | Haxe+muse.pd interp/JS | not WASM/VM |
| Parquet ingest grant | Node `hyparquet` | **U** fitness |

---

## 2. Opaque-U / deferred ridges (checklist)

### A. WASM + VM frames / Index (cliff: **frames**)

| # | Ridge | Engines | Anchor | Owner |
|---|-------|---------|--------|-------|
| A1 | All frame-returning `pd_*` → whole-module **U** (opaque `TDataFrame`/`TIndex`) | WASM **U**; VM **U** | `WasmPdEligibility.HOST_ESCAPE`; `StrategyWasmEmitter.isOpaqueObjectType` (`TDataFrame`/`TIndex`); `VmPdEligibility.UNSUPPORTED`; `docs/WASM_PD.md` § Escape | **frames** |
| A2 | Construct/select: `pd_from_columns`, `pd_dataframe`, `pd_get`, `pd_select`, … | WASM **U**; VM **U** | `HOST_ESCAPE` L46–52; `VmPdEligibility.UNSUPPORTED` L59–65 | **frames** |
| A3 | Join/align: `pd_join`, `pd_merge_asof`, `pd_reindex`, `pd_align`, concat | WASM **U**; VM **U** | same | **frames** |
| A4 | Groupby / pivot / melt / corr / cov | WASM **U**; VM **U** | `HOST_ESCAPE` L58–61 | **frames** |
| A5 | Rolling / ewm / `pd_resample` / frame `pd_rank` / `pd_xs_rank` | WASM **U**; VM **U** | `HOST_ESCAPE` L60–65; `docs/WASM_PD.md` L25–26 | **frames** |
| A6 | MultiIndex / factorize flats on VM/WASM | WASM **U**; VM **U** | `HOST_ESCAPE` L67–69; VM L76–78 | **frames** |
| A7 | Expand wide xs_rank (`\|universe\| > 64`) → one-row frame path | WASM **U**; Fitness VM refuses | `Expand.pdXsRankExpr` L364–366; `Palette.PD_RANK1D_MAX`; `Fitness.evaluateVm` L438–440 | **frames** + **evo-palette** |
| A8 | `Fitness.evaluateVm` panel / `KPd("xs_rank")` early **U** | VM | `Fitness.hx` L433–440; `vm/README.md` L21–23 | **frames** |
| A9 | NMA refuse closed `KPd` (incl. xs_rank + shift) | NMA `nma-unsupported` | `Fitness.evaluateNma` L633–637; `NmaBijection.scalarFromEnum` KPd throw | **nma** (consume/fallback) / **frames** (if columnar PD ever) |

### B. Series handle asymmetry (cliff: **wasm-series** + **series-meta**)

| # | Ridge | Engines | Anchor | Owner |
|---|-------|---------|--------|-------|
| B1 | WASM Series still opaque **U** (`pd_series` / `pd_shift` / `pd_series_values` in `HOST_ESCAPE`) | WASM **U**; VM **H** | `WasmPdEligibility.HOST_ESCAPE` L46–50, L62; `docs/WASM_PD.md` matrix Series column; `vm/README.md` L94 | **wasm-series** |
| B2 | Expand `KPd("shift")` → `pd_series`/`pd_shift`/`pd_series_values` chain | WASM whole-module **U**; VM Series **H** (preferVm eligible) | `Expand.pdShiftExpr` L373–380; `Fitness` header L36–38 | **wasm-series** |
| B3 | Series ctor index/name args (arity>1) | VM **U** (arity gate); WASM **U** | `VmPdEligibility.arityOk` `pd_series`: argc==1; `vm/README` Deferred L96–97 | **series-meta** |
| B4 | `pd_series_name` / `pd_series_length` scalars | VM **U**; WASM **U** | `VmPdEligibility.UNSUPPORTED` L63; `WasmPdEligibility.HOST_ESCAPE` L50 | **series-meta** |
| B5 | Frame form of `pd_shift` | VM **U**; WASM **U** | `VmPdEligibility` header L20–21; VM UNSUPPORTED does not list `pd_shift` as HEAP only Series | **series-meta** / **frames** |
| B6 | Descending / non-literal pct / len>64 `pd_rank1d` | WASM **H**; VM **U** | `docs/WASM_PD.md` L23; `VmPdEligibility` L44; `TestWasmNp` over-cap twin | **wasm-np** (cap twin ✅) / **frames** |

### C. Open bags / panel HostABI escapes (cliff: **open-bags**)

| # | Ridge | Engines | Anchor | Owner |
|---|-------|---------|--------|-------|
| C1 | Open `bag_rank_mom` / `bag_rank_rsi` / `bag_rank_field` / `bag_computed` / `bag_graph` | WASM **U**/escape; out of Expand+NMA | `PANEL_HOST_ESCAPE` L1663–1669; `docs/WASM_PD.md` L74–76, L106 | **open-bags** |
| C2 | `symbols()`, free-standing `bag_from_scan` / `bag_norm` / `bag_equal` / assigned `var b = bag_*` | WASM opaque **U** | `WASM_PD.md` L106–107; `StrategyWasmEmitter` L1380–1381 | **open-bags** |
| C3 | HostABI `bottom` scan (`bag_from_scan(…, bottom=true)`) | stays opaque | `matchClosedBagApplyArg` L1749–1751; `WASM_PD.md` Follow-ups L142 | **open-bags** |
| C4 | Packed bag locals across statements | still **U** | `WASM_PD.md` L142 | **open-bags** |
| C5 | Open panel genomes / non-NMA panelAction | NMA `nma-unsupported` → Expand | `Fitness` L652–654; `NmaFitness.evaluatePanel` L229–232 | **open-bags** / **nma** |
| C6 | Pending-book / brackets / OCO / `portfolio_long|short|flat` / group alloc | WASM **H** host_eval | `PANEL_HOST_ESCAPE` L1672–1677; `docs/WASM_NP.md` L173–179 | **open-bags** (panel surface) |

### D. NMA gaps (cliff: **nma**)

| # | Ridge | Backend | Anchor | Owner |
|---|-------|---------|--------|-------|
| D1 | **All** closed `KPd` → `nma-unsupported` (xs_rank *and* shift) | Expand→interp/JS/WASM | `Fitness.evaluateNma` L633–637; evo `README.md` L48–52 | **nma** |
| D2 | Open `bag_rank_*` / unsupported panelAction | Expand | `NmaFitness` L229–232; `PanelInline.isNmaPanelAction` | **nma** + **open-bags** |
| D3 | Sim-coupled roots / position KFeature on panel NMA | Expand | `NmaFitness` L241–244, L204–206 | **nma** |
| D4 | `BFeature` opaque leaves / nested-source SInd / KFeature | Expand | `NmaBijection`; `Fitness` L701+ | **nma** |
| D5 | PSHost/PSNoise projections | Expand decorate | `Fitness.evaluateNma` L628–630 | **nma** (out of PD scope but preferVm chain) |
| D6 | Entire `muse.np` outside closed window mean/sum/dot | `nma-unsupported` class | `docs/WASM_NP.md` NMA row; `ENGINE_MATRIX` NP NMA | **nma** / **evo-palette** |
| D7 | Columnar PD for gated `KPd` genomes | still Expand today | `WASM_PD.md` Follow-ups L139; `NmaBijection` KPd throw | **nma** ⭐ high leverage if evo wants PD hot path |

### E. muse.np residual H/U (cliffs: **wasm-np** / **vm-np**)

| # | Ridge | Engines | Anchor | Owner |
|---|-------|---------|--------|-------|
| E1 | Residual `HOST_ESCAPE` (reshape, fancy index, comparisons, outer, arange/eye, …) | WASM **H** (documented) | `WasmNpEligibility.hx`; `docs/WASM_NP.md` § Residual | **wasm-np** ✅ closed subset 2026-08-05; remainder deferred |
| E2 | Axis ≠ {0,-1} / `keepdims=true` / multi-dim create | WASM **H**; VM **U** | emit `assertNpAxis0Ok`; keepdims/ND stay H | **wasm-np** / **vm-np** — axis∈{0,-1} keepdims=false **N** for min/max/prod/std/var too |
| E3 | Over `MAX_VEC_LEN` 64 / matmul side >8 | WASM **H** (intentional caps) | caps + `TestWasmNp.testEscapeMatmulOverSideAndRank1dOverCap` | **wasm-np** ✅ documented+tested |
| E4 | Risk helpers `np_vol_target_qty` / `np_mask_qty` / `np_rolling_log_vol` | WASM **H**; VM **U** | stay HOST_ESCAPE | **wasm-np** ✅ deferred H (honesty) |
| E5 | VM: most ufuncs + `np_exp`/`np_log`/`np_cumsum`/`np_matmul`/… | VM **H** (closed) | `VmNpEligibility.HEAP_ND` | **vm-np** ✅ |
| E5b | VM↔WASM NP asym close: abs/sqrt/unary + minmax + min/max/prod/std/var/size/ndim | VM **H**/**B** (closed) | `VmNpEligibility` + `TestBytecodeVmParity` | **vm-np** ✅ 2026-08-05 |
| E6 | VM runtime-element `asarray([close,…])` | VM **H** (closed); WASM **N** | `PACK_ARRAY` + `assertAsarray1dOk` | **vm-np** ✅ |
| E7 | Optional evo `NP_MATMUL` / mask qty palette | gated off | `WASM_NP.md` L191; `_prior_ndarray_plan` | **evo-palette** |

### F. Ingest / product never / hygiene (cliff: **series-meta** / platform)

| # | Ridge | Notes | Anchor | Owner |
|---|-------|-------|--------|-------|
| F1 | `pd_read_csv` / `pd_read_parquet` fitness **U** unless grant | by design | `WASM_PD.md` L41–42 | ingest (not evo hot) |
| F2 | Series-of-strings typed handle | **not planned** — Str sidecar | `WASM_PD.md` L136–137 | product never |
| F3 | Arrow writer; open Dynamic melt `value` | deferred | `WASM_PD.md` L137 | **frames** comfort |
| F4 | Python `#if muse_pd_pandas` polish; JVM join accel | deferred | `_pandas_dataframe_plan.md` L354, L501 | platform |
| F5 | Deeper checker `TDataFrame` ≠ `TSeries` | deferred | `WASM_PD.md` L140 | **frames** |
| F6 | Engine-matrix CI beyond Node | deferred | `WASM_PD.md` L141; plan L504 | platform / **series-meta** |
| F7 | Dynamic score bags in examples | opportunistic | plan L504 | **open-bags**/examples |
| F8 | Open groupby/merge in Expand | **NEVER** | plan / Palette | do not implement |

### G. preferVm / Fitness unsupported paths (all cliffs consume)

| # | Path | Trigger | Fallback | Anchor |
|---|------|---------|----------|--------|
| G1 | `vm-unsupported` panel | `usesPanelFitness` / `hasPanelOf` | Expand→interp/WASM | `Fitness.evaluateVm` L433–435 |
| G2 | `vm-unsupported` `KPd("xs_rank")` | Expand panel/frame | Expand→interp/JS | L438–440 |
| G3 | `vm-unsupported` host projection refs | `ProjectionProvider.hostProjRefs` | Expand | L441–442 |
| G4 | `vm-unsupported` AST / compile miss | `VmUnsupported` / null chunk | Expand | L454–459 |
| G5 | `KPd("shift")` *may* hit VM | Series H chain in Expand | preferVm ON | docs + evaluateVm (no early refuse) |
| G6 | Hand-written `pd_rank1d` ≤64 | VM **H** eligible | — | `vm/README` L66–67 |
| G7 | NMA first when `preferNma`; else VM; else compile | chain order | — | `Fitness.evaluate` L401–421 |

### H. BYTECODE_VM residual (non-pd, still tree-walk)

Keep visible so parallel agents don't confuse with PD cliffs: objects/arrays/match/loops/generators, multi-arg orders, user-`@indicator` `__cs`, registry opaques as CALL_BUILTIN, Tier B gated.  
Anchors: `BYTECODE_VM_TODO.md` P2+/P3; `vm/README.md` § Still tree-walk.

---

## 3. Expand U markers (closed palette)

| Expand shape | When | Tag | File |
|--------------|------|-----|------|
| `np_get_flat(pd_rank1d([...], true), i)` | `\|syms\| ≤ PD_RANK1D_MAX` (64) | WASM **N** / VM **H** | `Expand.hx` L360–362 |
| `np_get_flat(pd_series_values(pd_get(pd_xs_rank(pd_from_columns({…})), sym)), 0)` | `\|syms\| > 64` | opaque frame **U** | `Expand.hx` L364–366 |
| `np_get_flat(pd_series_values(pd_shift(pd_series(window(f,w)), p)), last)` | `KPd("shift")` | WASM Series **U**; VM Series **H** | `Expand.hx` L373–380 |
| Closed bags → `portfolio_apply(bag_from_scan\|bag_norm(…))` | gated PD+universe | HostABI hybrid | `Expand` panelAction path; `WASM_PD.md` § Panel closed bags |
| Open `bag_rank_*` / `symbols()` | — | **never** in Expand | `Palette.hx` L27–37 |

`Palette.PD_OPS = ["xs_rank","shift"]` — no further PD growth without evo-palette decision.

---

## 4. Ownership map (who picks which ridge)

```
frames ──────── A1–A8, F3, F5, (A9 absorb if columnar PD)
wasm-series ─── B1–B2          ★ asymmetry vs VM Series H
series-meta ─── B3–B5, F*
nma ─────────── D1–D7, A9      ★ KPd still Expand-only under --nma
open-bags ───── C1–C6
wasm-np ─────── E1–E4, B6(cap)
vm-np ───────── E5–E6
evo-palette ─── E7, A7 policy, new PD_OPS
```

---

## 5. Top leverage ranking (for implementers)

See closing section in agent return — highest evo/fitness heat first.

---

## 6. Refresh protocol

When closing a ridge: tick here, update twin docs (`WASM_PD`/`WASM_NP`/`ENGINE_MATRIX`/`vm/README`), eligibility arrays, and a parity test (`TestWasmNp` / `TestPdM4` / `TestBytecodeVmParity` / `TestNpPdEvoPalette` / `TestPanelWasmParity` as relevant). Never claim **N** without a matrix row.
