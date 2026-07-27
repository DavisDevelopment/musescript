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
| **Implementation still under** | `musescript/indicators/ew/*` (temporary) |

Hard EW grammar stays non-learnable. Soft φ / guideline weights (`EwPhiParams`) are
learnable. MCMC (when landed) samples **rule-valid** labelings; soft params sit in an
outer loop. OHLCV-first. Emit probabilistic counts / bands / invalidations first;
trading signals are derived consumers.

## Evo handoff (Claude)

Do **not** wire EvolutionEngine / Fitness / Variation from this package session.
Claude owns forecasting integration in evo. Consume:

- `ForecastCloud` / `EwForecastHost` as the EW boundary (**boundary X** in `ARCHITECTURE.md`)
- Gene sketch + fitness principles in `BRAINSTORM_COEVOLVE.md` (docs only)

## Related

- Handbook direction palette: `indicators/ew/handbook/BRAINSTORM.md`
- General projection co-evolution (non-EW): repo root `PROJECTION_COEVOLUTION_PLAN.md`
- Streaming facade today: `indicators/lib/EwHypothesisIndicator.hx` → GeomViz
