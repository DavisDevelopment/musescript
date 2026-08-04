# WASM `muse.pd` eligibility (honesty)

Tabular DataFrame / PdSeries handles are **opaque objects** — not packed into
`VEC_SCRATCH`. After `MuseHostLower`, authors write `muse.pd.*` → flat `pd_*`.

Source of truth: `musescript/compile/WasmPdEligibility.hx` (+ opaque tagging in
`StrategyWasmEmitter.isOpaqueObjectType` for `TDataFrame` / `TPdSeries` /
`TIndex`). Twin of `docs/WASM_NP.md`.

## Caps

None claimed. A future 1-D native `pd_xs_rank` / `pd_shift` would mirror
`WasmNpEligibility.MAX_VEC_LEN` (64); **not shipped in M3**.

## Native subset (**N**)

| Op | Shape | Notes |
|----|-------|-------|
| *(none)* | — | M3 ships **zero** claimed-native `pd_*` |

Do not invent silent native frame kernels. Rank/zscore on packed f64 scratch is
a follow-up only after emitter + DetMath + Expand tests exist.

## Escape / unsupported (**H** / **U**)

| Tag | Meaning for `pd_*` |
|-----|--------------------|
| **H** | Would be per-statement `host_eval` if DataFrame round-trip through escape regions worked — it does **not** today |
| **U** | Practical WASM stance: any strategy calling a builtin that **returns** `TDataFrame`, `TPdSeries`, or `TIndex` forces **whole-module fallback** (interp/JS), same honesty class as `TProbCloud` / `TBag` |

Documented catalog (representative of all `pd_*`): see
`WasmPdEligibility.HOST_ESCAPE` — construct/select, merge_asof/join, groupby,
pivot/melt, corr/cov, rolling/ewm, grant CSV, etc. Unlisted `pd_*` is also
escape / unsupported.

`pd_read_csv` remains **U** on WASM fitness and **U** on other engines unless
`IoGrant` is attached (ingest tier).

## Engine matrix (M3)

| Engine | Construct / select | merge_asof / join | groupby / pivot / corr | rolling / xs_rank | read_csv |
|--------|--------------------|-------------------|------------------------|-------------------|----------|
| **Interp** | **N** (Haxe) | **N** | **N** | **N** | **U** unless grant |
| **JS** | **B** (`pd_*`) | **B** | **B** | **B** | grant / Studio |
| **Bytecode VM** | **U** | **U** | **U** | **U** | **U** |
| **WASM** | **U** (opaque fallback) | **U** | **U** | **U** | **U** |
| **NMA** | Don't force frames into kind-switch | — | — | — | — |

## Evo palette `PD_*`

**Shipped (gated, default off):** `KPd("xs_rank", …)` via
`Variation.configureForPd` **and** `configureForUniverse` (or
`configureForPanel`, which sets the universe). Expand emits a literal one-row
`pd_from_columns` + **percentile** `pd_xs_rank(..., true)` cell extract — no
open groupby/merge/HTTP — and coerces onto `PanelAction` / `target_weight` so
selection scores via `Fitness.configurePanel` → `runPanelBacktest`.

Enable trio:

```text
engine.configureForPanel(panel)
engine.configureForPd(null)       # or ["xs_rank"]
# universe comes from panel; or configureForUniverse([...]) without panel growth-only
```

NMA/VM/WASM stay unsupported / all-U → Expand→interp/JS. Columnar NMA for PD
frames remains deferred.

`PD_SHIFT` remains deferred (use `KLookback` / series lookback instead).

## Follow-ups

- Optional tiny **N**: 1-D `pd_xs_rank` / `pd_shift` ≤64 scratch + goldens
- Columnar NMA / bag Expand for PD-bearing genomes (still Expand→interp today)
- Deeper checker enforcement of `TDataFrame` ≠ `TSeries`
- Engine-matrix CI jobs beyond Node pd gate
- MultiIndex for multi-key agg index (M4+)
