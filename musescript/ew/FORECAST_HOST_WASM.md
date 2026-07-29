# Forecast Host WASM / JS runtime — handoff for Forecast Panel (2.2–2.5)

**Initiative 2.1 deliverable.** Browser-callable hosts with JVM↔JS byte-identity proof.

## What compiles

| Artifact | Command | Role |
|---|---|---|
| `build/js/forecast-host-runtime.js` | `haxe build-forecast-host-runtime.hxml` | `@:expose("ForecastHostRuntime")` browser module (same pattern as `muse-runtime.js`) |
| `build/js/forecast-host-parity.js` | `haxe build-forecast-host-parity-node.hxml` | Node parity dump |
| `build/jvm/forecast-host-parity.jar` | `haxe build-forecast-host-parity-jvm.hxml` | JVM parity dump |

Parity gate: `tools/forecast_host_parity_ci.ps1` / `.sh` — JVM == node == `testdata/forecast-host-parity.golden.txt`.

Overlay API smoke: `node tools/forecast_host_overlay_smoke.js` — auction `state.bins` + lattice `ensembles`.

Hosts covered in the parity transcript: **regime**, **auction**, **lattice**.

> Note: “WASM” here follows the museRuntime convention — Haxe dual-compile to JS for
> in-browser execution, with `DetRng`/`DetMath` guaranteeing byte-identical numerics vs JVM.
> A future true wasm32 binary can reuse the same host classes unchanged.

## Overlay API (`ForecastHostRuntime`)

```js
import "./forecast-host-runtime.js"; // or <script> — exposes ForecastHostRuntime

ForecastHostRuntime.kinds(); // ["regime","auction","lattice"]

const out = ForecastHostRuntime.forecast(kind, bars, opts);
// bars: [{open,high,low,close,volume?,time?}, ...]  (index assigned 0..n-1)
```

**Common opts:** `queryAt` (bar index; default = last), `all: true` (every bar), `includeCounts` (default true), `countK`.

| kind | Key opts | Cloud meaning for overlays | Extra `state` / extras |
|---|---|---|---|
| `regime` | `seed`, `horizon`, `window`, `steps`, `burnIn`, `nPaths`, `k`, `persist` | Band = predictive p05–p95 cone; `labelCode` = regime id; `countEntropy` = ambiguity | — |
| `auction` | `window`, `bins`, `valueAreaPct`, `horizon`, `includeBins` (default true) | `priceLo/Hi` = VA; `priceMid` = POC; `probUp` = discovery-up mass | `{ regime, poc, vaHigh, vaLow, valueAreaVolFrac, bins:[{price,vol}] }` |
| `lattice` | `k`, `fineThreshold`, `includeEnsemble` (default true) | Fan via `counts[].masses` + `ensembles[].bands` (opacity ∝ mass); `invalidatePrice`; `countEntropy` | `ensembles:[{t,bands:[{label,mass,priceLo,priceHi,barLo,barHi,kind,invalidatePrice}]}]` |

**Return shape (ok):**
```js
{
  ok: true,
  kind,
  clouds: [{ t, horizon, priceLo, priceHi, barLo, barHi, priceMid, spread,
             probUp, topMass, countEntropy, invalidatePrice, distToInvalidation,
             nestScore, labelCode, samples }],
  counts?: [{ t, masses: [{ label, mass, score, invalidatePrice, nestScore, degree }] }],
  ensembles?: [{ t, bands: [...] }],  // lattice multi-count fan
  state?: { ... } // auction profile levels + bins
}
```

Failures never throw: `{ ok:false, error }`.

## Mobile / glcharts wiring (2.2–2.5)

| Piece | Path |
|---|---|
| Runtime copy | `mobile/src/lab/forecast-host-runtime.js` (refresh: `cp build/js/forecast-host-runtime.js …`) |
| Client facade | `mobile/src/lab/forecastHostClient.js` (pins `ForecastHostRuntime` on globalThis) |
| Overlay pack | `mobile/src/glcharts/forecast/` — `register.js` / `compute.js` / `paint.js` |
| Catalog ids | `FC_EW`, `FC_REGIME`, `FC_AUCTION` (category **Forecast**) |
| Paint path | `indicatorsPaint` → `paintForecastPanel` (Canvas2D on GL overlay; honesty tag always) |
| Menu | GlChartPanel `+ ind` → **Forecast · projected** |

Live regime uses reduced MCMC (`steps≈400`, `nPaths≈80`) + ~280ms debounce (`glcharts:forecast-ready` redraw).

## What 2.2–2.5 needs from this host API

| Item | Overlay | Consume from host | Status |
|---|---|---|---|
| **2.2 EW** | Fan of alternate counts + invalidation + entropy | `kind:"lattice"` → `ensembles` / `counts` + `invalidatePrice` + `countEntropy` | Landed (`FC_EW`) |
| **2.3 Regime** | Vol-regime shading + forward cone + badge | `kind:"regime"` → cone + `labelCode`/`topMass` | Landed (`FC_REGIME`; trailing wash = current regime, not per-bar MH) |
| **2.4 Auction** | Volume-profile hist + VA + POC + balance/discovery | `state.{poc,vaHigh,vaLow,regime,bins}` | Landed (`FC_AUCTION` + `state.bins`) |
| **2.5 glcharts** | Port Forecast Studio Canvas → WebGL overlay | Canvas2D paint on GL chart overlay (same layer as GeomViz) | Landed |

## Checklist for follow-ons

- [x] Copy/link `forecast-host-runtime.js` into `mobile/src/lab/` like `muse-runtime.js`
- [x] Debounce for regime MCMC on live ticks (first cut; full worker optional)
- [x] Export auction histogram bins in `state` for 2.4 hist draw
- [x] `ensembleAt` bands on lattice JS facade (`includeEnsemble`)
- [ ] Wire `forecast_host_parity_ci` into CI (pipeline-hardening workflow)
- [ ] True wasm32 target only if JS bundle size / perf demands it — hosts are already Det*-safe
- [ ] Optional: Web Worker for regime MH so UI thread never stalls on large `steps`
- [ ] Optional: per-bar regime shading via cheap label cache (not full MH per bar)
