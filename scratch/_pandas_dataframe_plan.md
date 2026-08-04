# MuseScript pandas-like stack (`muse.pd`) — Engineering Plan

**Status:** M0 + M1 + M2 + M3 landed (Haxe core + muse.pd spine; no fitness pandas).  
**Workspace:** `muse-script` (Haxe 5.0.0-preview.1).  
**Sister plan:** `scratch/_prior_ndarray_plan.md` (NdArray / `muse.np` M0–M2+ — **landed skeleton**).  
**Governing doctrine:** `JIT_AUTHORING_GUIDE.md`, RingBuffer / GrowableVec / FloatSeries, `SPEC_BYTECODE_VM.md` (DetMath), `Palette.hx` evo boundary, `MuseHost.hx` + HostABI escape discipline, `IoGrant` / `PLUGIN_KINDS.md`, `docs/WASM_NP.md`, `docs/WASM_PD.md`.

---

## Research findings (compress — read before arguing)

### What already exists (compose, don’t fork)

| Surface | Role today | Relation to pandas-like |
|---|---|---|
| **`NdArrayF64/F32/I32/Bool` + `Np` + `muse.np`** | Columnar numeric core, strides/views, Broadcast, DetMath ufuncs, WASM eligibility honesty | **Columns of a DataFrame are `AnyNdArray` / preferred F64 views** — do not invent a second buffer type |
| **`NdBridge`** | GrowableVec / FloatSeries / `Bar.data` column / feature-tape → NdArray | Natural **Series constructors**; extend with `fromPanelFeed` / cross-section matrix |
| **`PanelFeed` + `PanelLoader`** | Calendar-aligned multi-symbol OHLCV + `auxSeries` from `Bar.data` | **Already a specialized wide panel** — long/wide frame factories should wrap this, not replace causal observe |
| **`PortfolioBuiltins.observePanel`** | One session `t` at a time into `field@SYM` series; fills optional next-open | **PIT law:** frame ops used *inside* strategy on_bar must not see `t+1`; bulk frame ops are offline / analysis / ingest |
| **`fund_panel_loader.py`** | EDGAR facts → merge-asof / forward-fill onto bars by `filing_date ≤ bar_date` | **Canonical asof semantics** to golden against; stay offline — no live EDGAR in runtime |
| **`MlBuiltins`** | Matrices still Dynamic-shaped `{rows,cols,data}` shimmed onto NdArray | Frames supersede ad-hoc feature matrices for authoring; keep ridge/matrix shims until M3 |
| **`BagBuiltins` / `scan_top` / `rebalance_equal` / `target_weight`** | Symbol→weight bags, literal panel actions | Consumers of **cross-section Series/frames** (scores → ranks → weights) |
| **`TSeries` (Muse)** | Live bar-series handle (OHLCV / aux), windowed indicators | **≠** `pd.Series`. Keep both: `TSeries` = streaming harness leaf; `TDataFrame`/`TPdSeries` = tabular objects |
| **`Palette` / Expand / NMA** | Closed OHLCV + gated `AUX_FIELDS`; panel genomes literal-of + PanelAction; NMA `nma-unsupported` for panels | **Never open-world groupby/merge in Expand** |
| **`IoGrant` / plugin kinds** | Default null grants; plugins deny `fs_*`/`http_*`/`db_*` | Ingest CSV/parquet/http = **grant-gated Studio/CLI**, never fitness default |
| **`WasmNpEligibility`** | Packed f64 scratch caps; host_eval fail-closed | Mirror for `pd_*`: native subset tiny or **all H/U until proven** |

### Engine targets (same as NdArray)

| Target | Stance for frames |
|---|---|
| **JS / Node** | Primary CI; **pure Haxe DataFrame default** |
| **JVM / Graal** | `@:multiType`-friendly column storage; pure Haxe kernels |
| **WASM** | Honesty first — almost everything host_eval / unsupported; optional tiny rank/zscore 1-D N later |
| **Python** | Opt-in `#if muse_pd_pandas` dual-track for goldens / experimental host consume — **never silent fitness** |
| **HL / C++** | Design-pluggable; not a ship gate |

### Explicit gap

There is **no** Index / Series / DataFrame type, no `muse.pd`, no join/groupby/asof in the Haxe library, and Muse `TSeries` means something else. Panel + bags + NdArray are the three islands this stack must weld.

---

## Part A — North-star product contract

1. **Haxe library** with a pandas-*feel* API where it matters for trading research — **zero `Dynamic` on the typed API**.
2. **Deep Muse exposure** (`muse.pd` / alias `muse.dataframe`) on every engine that *claims* support, with an eligibility matrix (**N / B / H / U**) as honest as `WASM_NP.md`.
3. **Fitness-visible paths** stay f64-default, DetMath where transcendentals appear, **PIT-safe**, memo-key stable, palette-gated for genomes.
4. **Compose** NdArray columns + PanelFeed bridges; **ingest IO is a separate tier** (grants) from **pure frame ops on already-loaded columns**.
5. **Not a full pandas clone.** Prefer “trading-critical pandas” first; general comfort API second; abandoned-npm parody never.

---

## Part B — Core types

### B.1 Recommended object model

```
Index          — ordered labels (Int / Float time / String); codes → positions
MultiIndex     — M4+ only (symbol × field, or time × symbol); defer until single Index solid
Series         — (name?, Index, values: AnyNdArray preferably F64 1-D)
DataFrame      — (Index row, ordered column names, columns: Map/Array of Series sharing Index)
BlockManager   — internal: columnar list of NdArray + shared Index (not row objects)
```

**Relationship to NdArray (frozen doctrine):**

| Claim | Rule |
|---|---|
| Column storage | **Is** an NdArray (view or owned). Default **F64**. String/categorical columns = **later / never on fitness**. |
| Row major “records” | Forbidden on hot API — no `Array<Dynamic>` rows. |
| Alignment | Ops align on **Index labels** (pandas-like), then dispatch NdArray ufuncs after reindex/take. |
| Views | `df["close"]` / `df.loc` / column select returns Series sharing buffer when contiguous & Index unchanged. Mutate-through-view tests required (same grade as NdArray M2). |
| vs Muse `TSeries` | Different type tags. Bridge: `PdBridge.fromHarnessSeries(harness, "close@AAPL")` copies or aliases prefix; never pretends streaming Series *is* a DataFrame column without an explicit snapshot. |

**Index design (M0–M1):**

- `IndexI64` / `IndexF64` (timestamps as f64 ms / unix — match `Bar.time`) / `IndexStr` (symbols).
- Codes stored as `NdArrayI32` position maps for join/reindex (RingBuffer doctrine: no `Map` on inner loops of large joins — build hash once then stream).
- Duplicate labels: **allow** but document; `groupby` / reindex must define first/last policy (pandas allows dups; Muse joins default **fail or take last** — decide D6).

**Series:**

- `.values` → NdArray; `.index`; `.name`; `.dtype` via NdArray; elemwise ops → aligned Series.
- Boolean masks → Series of Bool NdArray (`NdArrayBool`).

**DataFrame:**

- Construction: `fromColumns`, `fromRecords` (cold copy), `fromPanelFeed`, `fromNdArray(matrix, index, columns)`.
- Prefer **columnar** always; wide trading panels (`n_bars × n_syms`) are first-class.
- `toNdArray()` / `toMatrix()` for `muse.np` / ridge paths.

### B.2 Memory / layout

| Milestone | Layout |
|---|---|
| M0 | Owned F64 columns, shared Index, C-contig columns only |
| M1 | Reindex / take via `NdArrayI32` indexers; join outputs new frames |
| M2 | Column views (slice rows = strided NdArray + sliced Index); copy-on-write flag optional |
| M3+ | Categorical codes, sparse later — only if trading needs |

**Nulls:** Use **NaN** for float (panel already does). No pandas `NA` / ExtensionArray in M0–M3. Bool columns refuse NaN; missing → drop or explicit mask column.

---

## Part C — API catalog (phased)

### Phase P0 — Construct / inspect (trading bare metal)

| Op | Notes |
|---|---|
| `Series(data, index=, name=)` / `DataFrame(data=, index=, columns=)` | ArrayLike / NdArray / Map of columns |
| `fromPanelFeed(panel, fields=)` | Times × symbols for chosen fields; aux included |
| `fromBarDataColumn` / `NdBridge` wraps | Single-symbol long series |
| `head`/`tail`/`shape`/`columns`/`index`/`dtypes`/`copy`/`empty` | |
| `[]` column select, multi-col select | |
| `assign` / `drop` columns | |
| `reset_index` / `set_index` | |
| `reindex` / `take` / `iloc` (integer) | `loc` label later if Index hashing ready |
| `isna` / `fillna` / `dropna` | f64 NaN semantics |
| `concat` (axis 0/1) | |

### Phase P1 — Align / join / merge (**trading-critical**)

| Op | Priority | PIT note |
|---|---|---|
| **`merge_asof`** (backward / forward / nearest) | **Must** | Match `fund_panel_loader._forward_fill_onto_bars`; default **backward** = “last known ≤ t” |
| `merge` / `join` (inner/left/outer on keys) | Must | Symbol calendars, factor tables |
| `align` / binary ops with index align | Must | |
| `combine_first` | Should | |
| `concat` keys/`join=` | Should | |

### Phase P2 — groupby / cross-section (**trading-critical**)

| Op | Priority | Notes |
|---|---|---|
| `groupby(by).agg({sum,mean,std,count,min,max})` | Must | Single key first; MultiKey M3 |
| `groupby.transform` (broadcast back) | Must | zscore within date / sector |
| `groupby.rank` / `pct_rank` | Must | Cross-sectional ranks — portfolio DNA |
| `groupby.apply` (closed typed kernels only) | Later | No Python callables / Dynamic fn |
| `pivot` / `melt` / `stack`/`unstack` | Should | Wide↔long panel reshape |
| `crosstab` | Later | |

### Phase P3 — time / resample (**trading-critical subset**)

| Op | Priority | Notes |
|---|---|---|
| `resample(rule).agg` OHLCV-aware | Must | Calendar / business — start with fixed bar count / ms rules matching existing bars |
| `rolling` / `expanding` / `ewm` on Series | Must | Delegate windows to NdArray / existing ewm builtins where possible |
| `shift` / `diff` / `pct_change` | Must | |
| `asof` Series method | Must | Same semantics as merge_asof |
| Full `DateOffset` zoo / tz | Later / Never fitness | |

### Phase P4 — general pandas feel (comfort)

`sort_values`, `sort_index`, `nlargest`/`nsmallest`, `value_counts`, `describe`, `corr`/`cov` (→ muse.np), `clip`, `replace`, `map` (typed enum/dict only), `query` **Never** (parser in fitness = nightmare), `eval` **Never**, `pipe` mild sugar Later, `style` Never, `plot` → muse.chart bridge Later.

### Naming in Muse

```muse
df = muse.pd.from_panel(panel)          // host-provided snapshot — analysis / widget
xs = muse.pd.xs_rank(mom, axis="columns") // cross-section
w  = muse.pd.softmax_weights(xs)        // → bag / target_weight helper
fund = muse.pd.merge_asof(bars, facts, on="time", direction="backward")
```

Flat aliases: `pd_merge_asof`, `pd_groupby_mean`, … for Expand simplicity **only when palette-gated**.

---

## Part D — Missing vs pandas (ranked for Muse)

| Tier | Items |
|---|---|
| **Must** | Index+Series+DataFrame F64 columnar; construct from panel/bars/NdArray; reindex/align; merge/join; **merge_asof backward**; groupby agg/transform/rank; shift/diff/pct_change; rolling/ewm subset; fillna/dropna; concat; to/from NdArray; deep `muse.pd` on interp/JS |
| **Should** | pivot/melt; multi-key groupby; loc; resample OHLCV; corr/cov; categorical codes; PanelFeed zero-copy column views; tiny WASM N for rank/zscore 1-D; JVM `@:multiType` Index codes |
| **Later** | MultiIndex; sparse; string columns; Arrow / parquet reader (ingest tier); Method chaining sugar; SQL-like query; datetime Index tz; styler; plot helpers |
| **Never (Muse product / fitness)** | `dtype=object` / Dynamic cells; open `apply(λ)`; `eval`/`query` string exec; silent Python pandas in fitness; pickle protocol; full Excel/HTML IO; CUDA; “100% pandas parity” as a gate; **open groupby/merge graphs in Expand**; live http/db inside on_bar |

---

## Part E — Target backends + dependency pro/cons

### E.1 Accel policy (mirror `NdAccel`)

- **Default forever:** pure Haxe indexed loops over NdArray columns.
- **Python:** `#if muse_pd_pandas` dual-track — real pandas for fixture gen / optional host consume — **never** linked into fitness builds.
- **JVM:** pure Haxe / Java arrays; optional future `#if muse_pd_tablesaw` only behind parity (see table).
- **JS:** **no** numjs-style abandoned deps as silent core.

### E.2 Decision table — JS stack

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| **A. Pure Haxe DataFrame (columns = NdArray)** | One source of truth; DetMath/parity; matches NdArray doctrine; no npm roulette | Author velocity slower for niche APIs | **Default / required core** |
| **B. Wrap nothing beyond A** | Zero supply-chain; CI hermetic | No free lunch for viz notebooks | **Ship gate for Muse** |
| **C. Apache Arquero** | Maintained; expressive verbs; research lineage | Extra JS dep; parity vs Haxe split-brain; not in WASM fitness; Arrow-ish mindset ≠ our NdArray | **Optional Studio/notebook bridge only**, never fitness kernel |
| **D. Danfo.js** | pandas-like names | Heavier; TensorFlow.js gravity; version churn; easy to accidentally dual-implement | **Reject as core**; optional later notebook if Arquero loses |
| **E. tidy.js / pandas-js / data-forge** | Familiar verbs | Abandoned or niche; flaky | **Reject** |
| **F. Polars WASM** | Fast | Huge binary; Rust glue; fitness packaging hell | **Reject for Muse engines** |

### E.3 Python dual-track

| | `#if muse_pd_pandas` opt-in | Always call system pandas |
|---|---|---|
| **Pro** | Goldens = ground truth; research users happy | Zero ifdef |
| **Con** | Two codepaths to keep honest | Silent nondeterminism / version skew on Sharpe |
| **Verdict** | **Opt-in only; fitness flags forbid** | |

### E.4 JVM

| | Pure Haxe `@:multiType` columns | Tablesaw / Smile / join libs |
|---|---|---|
| **Pro** | Same as JS; Graal friendly | Faster joins |
| **Con** | Join perf DIY | Native deps, classpath, parity |
| **Verdict** | **Pure first; JNI/lib later behind parity gate like BLAS** | |

---

## Part F — Muse exposure (`muse.pd`)

### F.1 Host surface

| Mechanism | Role |
|---|---|
| `MuseHost` ns `pd` (+ alias `dataframe`) | Author UX parallel to `muse.np` |
| `PdBuiltins` | Flat `pd_*` + `build()` object |
| `BuiltinSigs` | `TDataFrame`, `TPdSeries`, `TIndex` (or reuse opaque handles carefully) |
| `MuseHostLower` | `muse.pd.foo` → `pd_foo` |
| JsBackend arity tables | Same pattern as `np_*` |
| PluginCapabilities | Frame **compute** allowed; IO readers classified `io_fs` / `io_net` |

**Do not overload Muse `TSeries`.** Streaming bar series stays `TSeries`; tabular series gets `TPdSeries` (name bikeshed: `TFrameSeries` if clearer).

### F.2 Engine eligibility matrix (initial)

| Engine | Construct / select / ufunc-via-np | merge_asof / join | groupby rank/agg | resample | read_csv |
|---|---|---|---|---|---|
| **Interp** | **N** (Haxe) | **N** | **N** | **N** subset | **U** unless grant |
| **JS** | **B** | **B** | **B** | **B** | grant / Studio |
| **Bytecode VM** | **U** or scalar-returning **B** only | **U** | **U** | **U** | **U** |
| **WASM** | **H** (host_eval) or **U** | **H/U** | **H/U** (maybe later N: 1-D rank ≤64) | **U** | **U** |
| **NMA** | Don’t force frames into kind-switch | — | — | — | — |

Publish `docs/WASM_PD.md` twin of `WASM_NP.md` — **fail closed**, no surprise host_eval in claimed-native lists.

### F.3 VM / opacity

Same lesson as NdArray D5: sealed `AnyDataFrame` / `AnySeries` handles at Muse boundary; **no** Dynamic row soup onto unboxed stack. M1–M2: prefer **scalar outputs** from pd ops on VM (`pd_xs_mean` → f64) or Expand→interp.

---

## Part G — IO plan (ingest vs fitness)

```
┌─────────────────────────────────────────────────────────────┐
│  INGEST TIER (Studio / CLI / Python tools)                  │
│  grants: IoGrant.fs / future net/db                         │
│  read_csv, read_parquet (later), http_get → bytes, db query │
│  fund_panel_loader / PanelLoader → PanelFeed / DataFrame   │
│  asof joins happen HERE for strategy tapes whenever possible│
└───────────────────────────┬─────────────────────────────────┘
                            │ already-loaded columns
┌───────────────────────────▼─────────────────────────────────┐
│  FITNESS / STRATEGY / PLUGIN COMPUTE                        │
│  pure muse.pd ops; muse.np on columns; no default grants    │
│  Panel observe still causal per t                           │
└─────────────────────────────────────────────────────────────┘
```

| Reader | Milestone | Gate |
|---|---|---|
| CSV (long / wide) | M1 ingest helpers wrapping PanelLoader patterns | `IoGrant` |
| Parquet | M3+ (Arrow/parquet.js / Python preconvert) | grant + optional dep pro/con again |
| SQLite/DuckDB | Prefer offline Python/CLI → JSON/panel today; `db_*` stubs M3 | grant |
| HTTP | Never in fitness; Studio only | `io_net` |

**Fitness law:** “I can load CSV in on_bar” is a **product bug**, not a feature.

---

## Part H — PIT / causality for asof joins on bars

### H.1 Laws (non-negotiable)

1. **Offline preferred:** fundamentals join onto bars in loaders (`filing_date ≤ bar_date`), identical to `_forward_fill_onto_bars`.
2. **Runtime `merge_asof`** must default `direction="backward"` and **refuse** forward-looking fills unless `allow_lookahead=true` (analysis-only flag; fitness harness sets false).
3. **`observePanel`:** even if a DataFrame of the full panel exists on the host, strategy code paths that use harness series only see index `t` — don’t add `muse.pd.panel_snapshot()` that returns future rows under fitness.
4. **Fill timing orthogonal:** `panelFillNextOpen` still governs order prices; factor frames at `t` use bar-`t` (or asof≤t) features.
5. **Growth derived series** keyed by later filing date (loader) — document asof on *derived* facts the same way.
6. **Goldens:** Python pandas `merge_asof` + loader fixtures must match Muse bit-for-NaN policy.

### H.2 API sketch

```
pd.merge_asof(left, right, on="time", by="symbol"?, direction="backward",
              tolerance=null, allow_lookahead=false)
```

`by=` enables per-symbol asof (panel long format). Wide panel: asof each column independently after melt, or specialized `asof_panel(facts, bars)`.

---

## Part I — Excessive tests + goldens

### Layers (copy NdArray grade)

1. **Haxe unit / property** — alignment corners, duplicate index policy, view aliasing, NaN propagation, groupby transform shapes.
2. **Python golden generator** — `tools/pandas_golden/gen_fixtures.py` (venv pandas + numpy); commit JSON; regenerate on demand. Cover: merge_asof, join hows, groupby rank/transform, resample edges, align add.
3. **Muse parity** — same `.ms` through interp ↔ JS; WASM assertions = “host_eval only when listed”.
4. **Panel PIT regression** — strategy at `t` cannot read asof value from filing `> t`; next-open fill unchanged.
5. **Fitness regression** — panel Sharpe smoke unchanged when scores flow Series→rank→`target_weight` via pd helpers.
6. **CI** — Node gate first; JVM slice for join kernels; optional pandas regen job.

**Volume target:** “excessive” = broadcast/join edge fixtures ≥ NdArray golden density for asof + groupby alone.

---

## Part J — Milestones M0–M4 (acceptance)

### M0 — Foundations (Haxe + Muse spine) ✅

**Delivered:** `Index` (F64 + Str), `Series`, `DataFrame` columnar F64; construct/select/copy/shape; `fromNdArray` / `fromColumns`; `Pd` facade; `PdBuiltins` + `muse.pd` (+ `muse.dataframe`) + BuiltinSigs (`TDataFrame`/`TPdSeries`/`TIndex`); bridges `fromBarDataColumn` / `fromBars` / `fromPanelFeed`.  
**Tests:** `TestPd` + `build-pd-tests.hxml` (construct, host lower, interp smoke).

### M1 — Align / asof / join + ingest CSV grant path ✅

**Delivered:** `Align.reindex`/`align`; `Join.onColumn`; `MergeAsof` backward (PIT `allow_lookahead=false`); fillna/dropna/concat; `PdCsv.readCsv` under `IoGrant` (`pd_read_csv` → `io_fs`); JsBackend/`BuiltinSigs` dispatch; goldens in `tools/pandas_golden/`.  
**Tests:** `TestPdM1` (asof goldens, grant deny, interp asof smoke).

### M2 — groupby / cross-section / rolling + panel bridges ✅

**Delivered:** `GroupBy` (single-key F64: agg mean/sum/min/max/count/std, transform incl. zscore, average-tie rank/pct); `FrameWindow` (shift/diff/pct_change, rolling mean/sum/min/max/std, ewm mean span); `xs_rank` wide-panel cross-section; Series/DataFrame methods; `Pd` + `PdBuiltins` flats (`pd_groupby_*`, `pd_xs_rank`, `pd_shift`, …); BuiltinSigs + MuseHost lower + JsBackend arity; causal rolling (no `center=`).  
**Tests:** `TestPdM2` (agg/transform/rank, xs→recipe, windows, interp `groupby_rank` smoke).  
**Accept:** Factor long → groupby date rank; wide panel → `xs_rank` without Dynamic score bags.

### M3 — Deep muse.pd + honesty docs + opaque hygiene ✅

**Delivered:** `FrameReshape` pivot/melt; multi-key `GroupBy.createKeys` (agg `as_index=False` shape; MultiIndex M4+); `FrameCorr` pearson corr + sample cov; sealed `AnyDataFrame` / `AnyPdSeries` + `AnyPdValues`; `WasmPdEligibility` (native subset empty) + `docs/WASM_PD.md`; `TDataFrame`/`TPdSeries`/`TIndex` marked opaque in WASM emitter (whole-module fallback); Muse flats `pd_pivot`/`pd_melt`/`pd_corr`/`pd_cov`/`pd_groupby_keys_agg`.  
**PD_* evo palette:** **gated closed set** — `KPd` / `configureForPd` + universe
emits one-row `pd_xs_rank` only (no open groupby/merge). Default off.
`PD_SHIFT` still deferred (use lookback). See `Palette.PD_OPS` / `TestNpPdEvoPalette`.
**Tests:** `TestPdM3` (reshape, multi-key, corr, Any*, eligibility, opaque fallback, interp pivot smoke).
**Accept:** Published eligibility table; authored strategies rich on interp/JS; genomes stay closed (no open pd Expand).

### M4 — Time resample + parquet ingest + optional accel

**Deliver:** resample OHLCV; parquet ingest option (pro/con locked); Python `#if` dual-track polished; optional JVM join accel behind parity.  
**Accept:** Must-tier green on Haxe+Muse interp/JS; WASM/VM matrix published; never-tier still never.

---

## Part K — How this enables trading APIs

| Trading need | Frame move | Downstream |
|---|---|---|
| **Factor frames** | Long `(time,symbol,factor)` or wide `time × symbol` | merge_asof onto price panel; groupby transform zscore |
| **Panel cross-sections** | One row = all symbols at `t`, or Xs Series | `rank` / `pct_rank` → `scan_top` / bag weights |
| **Sizing matrices** | `n_sym × n_bucket` NdArray inside frame, or weights Series | `target_weight` / `portfolio_apply` / softmax helpers |
| **Fundamentals PIT** | Facts table × bars asof | Already loader; runtime asof for research notebooks |
| **Multi-field scores** | DataFrame of momentum/value/quality → combine | `muse.np` on `.values` / column ops |
| **Projections / CCEA** | Projection feature packs as frames before NdArray | Keep causal seams; frames are host-side feature factories |
| **Widgets / scanners** | `muse.pd` compute kind OK; no orders/IO | FlexLayout tables without reinventing grids |

**Explicit non-goal for genomes:** evolving arbitrary join graphs. Prefer: pre-joined tape + closed `PD_XS_RANK(scores)` style nodes.

---

## Part L — Decision pro/con tables

### D1 — Column storage

| | NdArray columns (recommended) | Separate Series buffer type |
|---|---|---|
| **Pro** | One numeric stack; free ufuncs/strides | Simpler frame-only mental model |
| **Con** | Index align layer still needed | Duplicate kernels forever |
| **Verdict** | **NdArray columns** | |

### D2 — Muse type split

| | New `TPdSeries`/`TDataFrame` (recommended) | Overload `TSeries`/`TMatrix` |
|---|---|---|
| **Pro** | No footguns with window()/sma | Fewer types |
| **Con** | More BuiltinSigs | Streaming vs tabular fusion bugs |
| **Verdict** | **Split types** | |

### D3 — JS dependencies

| | Pure Haxe only (recommended) | Arquero alongside |
|---|---|---|
| **Pro** | Hermetic fitness | Notebook ergonomics |
| **Con** | Build APIs ourselves | Split-brain risk |
| **Verdict** | **Pure core; Arquero optional Studio-only later** | |

### D4 — Python pandas

| | Opt-in `#if` goldens (recommended) | Runtime always-on |
|---|---|---|
| **Pro** | Truth fixtures | Author convenience |
| **Con** | Maintain generator | Fitness lies |
| **Verdict** | **Opt-in; fitness ban** | |

### D5 — WASM depth

| | Honest H/U until proven (recommended) | Early native groupby |
|---|---|---|
| **Pro** | Matches WASM_NP maturity | Fitness speed |
| **Con** | Slow escaped paths | Emitter explosion, PBO risk |
| **Verdict** | **H/U first; optional 1-D rank N later** | |

### D6 — Duplicate Index labels

| | Allow + document (pandas-like) | Forbid in M0 |
|---|---|---|
| **Pro** | Real market data has quirks | Simpler joins |
| **Con** | join ambiguity | Strictness friction |
| **Verdict** | **Allow; join default `validate` opt; asof takes last ≤ t** | |

### D7 — Genome growth

| | Closed palette PD_* only (recommended) | Open `muse.pd` in Expand |
|---|---|---|
| **Pro** | Honesty, WASM-ability | Novelty |
| **Con** | Less expressive genomes | Undebuggable search, host_eval storm |
| **Verdict** | **Palette-gated** | |

### D8 — Namespace

| | `muse.pd` + `muse.dataframe` alias (recommended) | Only flat `pd_*` |
|---|---|---|
| **Pro** | Matches muse.np story | Minimal |
| **Con** | Lowering work | Feels bolted |
| **Verdict** | **`muse.pd` primary** | |

### D9 — When asof runs

| | Prefer ingest-time asof (recommended) | Runtime asof always |
|---|---|---|
| **Pro** | Fitness tapes simple; PIT audited once | Flexible research |
| **Con** | Re-run loader to change join | Easy lookahead bugs |
| **Verdict** | **Ingest default; runtime asof for research + gated allow_lookahead** | |

---

## Part M — Anti-goals

- **No Dynamic cell DataFrames** (object dtype).
- **No silent Python pandas in fitness / WASM / evo oracles.**
- **No open-world groupby / merge / apply in Expand** — closed palette only.
- **No shipping Haxe-only frames claiming Muse-ready** without BuiltinSigs + engine matrix.
- **No flaky abandoned JS DF deps as the core.**
- **No query/eval string languages** inside strategy runtime.
- **No live EDGAR/http/db inside on_bar** (Palette / IoGrant / PluginKinds already say this).
- **No pretending full pandas in M0–M1.**
- **No megamorphic row-object kernels** on JVM/V8 — columnar NdArray loops only.
- **No MultiIndex / sparse / ExtensionArray before asof+groupby are boringly correct.**
- **No conflating Muse streaming `TSeries` with `pd.Series`.**

---

## Part N — Module layout (proposed)

```
musescript/dataframe/          # Haxe core
  Index.hx / IndexF64.hx / IndexStr.hx
  Series.hx
  DataFrame.hx
  Align.hx / Join.hx / MergeAsof.hx
  GroupBy.hx / Resample.hx / Rolling.hx
  Pd.hx                        # facade
  PdAccel.hx                   # pure default + #if stubs
  bridge/PdBridge.hx           # PanelFeed, Bar, NdBridge, bags

musescript/builtins/PdBuiltins.hx
musescript/types/ — TDataFrame, TPdSeries, TIndex; BuiltinSigs; PluginCapabilities rows
musescript/compile/ — MuseHost ns, JsBackend, WasmPdEligibility (+ docs/WASM_PD.md)
tools/pandas_golden/ — gen_fixtures.py + fixtures/
musescript/tests/TestPd*.hx / TestPdMuseParity.hx / TestPdPit.hx
```

---

## Executive sequencing (one slide)

```
M0  Index+Series+DataFrame(F64 cols=NdArray) + muse.pd spine + Panel/Bar bridges
M1  align/join/merge_asof + grant-gated CSV + pandas goldens + PIT tests
M2  groupby/rank/transform + rolling + xs→portfolio path          ✅
M3  deep muse.pd + type tags + WASM_PD honesty + sealed Any*      ✅ (PD_* xs_rank gated)
M4  resample/parquet/opt-in accel + published engine coverage matrix
```

**Still deferred after M3:** MultiIndex; `PD_SHIFT` genome node; tiny WASM N for 1-D rank; engine-matrix CI beyond Node; parquet; deeper checker; resample OHLCV; killing Dynamic score bags in examples (opportunistic). Open groupby/merge in Expand stays **never**.

---

## Tiny signature sketches (non-normative)

```haxe
class Pd {
  public static function mergeAsof(left:DataFrame, right:DataFrame, on:String,
    ?by:String, ?direction:String = "backward", ?allowLookahead:Bool = false):DataFrame;
  public static function groupby(df:DataFrame, by:ArrayLike<String>):GroupBy;
  public static function fromPanelFeed(panel:PanelFeed, ?fields:Array<String>):DataFrame;
}

// Muse
// fun("pd_merge_asof", [TDataFrame, TDataFrame, TString, TString, TString, TBool], TDataFrame, 3);
// fun("pd_xs_rank", [TPdSeries], TPdSeries);
```

No implementation beyond this plan; no commit.
