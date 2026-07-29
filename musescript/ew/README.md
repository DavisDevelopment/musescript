# musescript.ew — forecasting / projection infra

Elliott Wave (and future MCMC-like projection engines) live here as a **first-class
infra leg**, not as a chart indicator. Streaming indicators may *consume* this package;
evolved agents co-evolve a **ForecastFn** (projection cloud) and **TradeLogic** that
reads cloud features.

## Status (this pass)

| Piece | Location |
|-------|----------|
| Architecture (paper × Muse × evo) | [`ARCHITECTURE.md`](ARCHITECTURE.md) |
| Co-evolution brainstorm + MVP | [`BRAINSTORM_COEVOLVE.md`](BRAINSTORM_COEVOLVE.md) |
| Package move plan | [`PROMOTE_PLAN.md`](PROMOTE_PLAN.md) |
| Stub surfaces | `ForecastCloud.hx`, `EwForecastHost.hx` |
| Lattice adapter | `LatticeForecastHost.hx` (**done**) |
| MCMC adapter (pragmatic) | `McmcForecastHost.hx` (**done** — top-K soft resampling) |
| Boundary X (evo) | `ProjectionProvider` + `PSHost` → trading + `projScore` (**done**) |
| Demo | CLI `HostProjectionCli` + JVM GUI `HostProjectionDemo` (see BRAINSTORM) |
| Browser host facade (2.1) | `ForecastHostRuntime.hx` + `FORECAST_HOST_WASM.md` — `haxe build-forecast-host-runtime.hxml` |
| Host JVM↔JS parity | `ForecastHostParityDump` + `tools/forecast_host_parity_ci.*` |
| Strategy forecast inputs (3.3) | [`FORECAST_STRATEGY_INPUTS.md`](FORECAST_STRATEGY_INPUTS.md) — `SProj` / `forecastFields()` |
| **Implementation still under** | `musescript/indicators/ew/*` (temporary) |

Hard EW grammar stays non-learnable. Soft φ / guideline weights (`EwPhiParams`) are
learnable. MCMC (when landed) samples **rule-valid** labelings; soft params sit in an
outer loop. OHLCV-first. Emit probabilistic counts / bands / invalidations first;
trading signals are derived consumers.

## Evo handoff (boundary X)

Consume:

- `ForecastCloud` / `EwForecastHost` as the EW boundary (**boundary X** in `ARCHITECTURE.md`)
- Gene sketch + fitness principles in `BRAINSTORM_COEVOLVE.md`

**Integration status:** Expand trading, φ genes, pragmatic MCMC, demo CLI/GUI — **DONE**.
See `BRAINSTORM_COEVOLVE.md` § Demo launch for exact commands.

## Related

- Handbook direction palette: `indicators/ew/handbook/BRAINSTORM.md`
- General projection co-evolution (non-EW): repo root `PROJECTION_COEVOLUTION_PLAN.md`
- Streaming facade today: `indicators/lib/EwHypothesisIndicator.hx` → GeomViz
