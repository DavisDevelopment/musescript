# WorldContext (Jormungandr ↔ MuseScript)

Schema freeze for P0 Desktop bridge. Built client-side from a ran `/world/simulate`
(or mock) outcome + `extractSimSeries` — no second simulate call.

## Envelope (`schemaVersion: 1`)

| Field | Meaning |
| --- | --- |
| `scenarioKey` | Stable hash of event ids + sim_seeds + remediation / mag / n_runs / seed |
| `runId` | Optional `/world/simulate/runs/{id}` |
| `eventIds` / `simSeeds` | Shock provenance |
| `seriesMeta` | horizon_days, n_steps, dt, fields |
| `fan.tDays` / `fan.nodes[]` | Activation means (+ optional p50/p90/pExceed), length-aligned |
| `controls` | seed, nRuns, counterfactual, remediation, magnitudeMultiplier |
| `generatedAt` | ISO-8601 |

Peak-only runs (no `nodes[].series`) **cannot** build a WorldContext — no fake envelopes.

## Aux columns on Muse bars

| Key | Meaning |
| --- | --- |
| `world_act_<nodeId>` | \|activation\| mean at aligned step |
| `world_p90_<nodeId>` | upper fan (optional) |
| `world_shock` | signed shock intensity (`dir * mag * max_act`) |
| `world_regime` | dominant-node index 0..K−1 |

## Alignment

- **calendar** (default when market bars provided): as-of join — fan sample with `t ≤ barSimDay` only (no lookahead). Desktop loads SPY via `worldMarketTape` (dataserver `/market/bars` + localStorage cache) and degrades to timestep with an honest tape badge when unreachable.
- **timestep**: one Muse bar per `tDays[k]`; synthetic OHLCV labeled in tape meta.

## Calibration (P1)

- Fan **forecast claims** resolve against peak `|activation|` → Brier chips on WorldSimPanel (never P&L).
- Unmapped nodes surface `observable_unmapped` / skip — no invented fans.
- Pre-commit slider scores P(real edge) vs Truth verdict after Light Muse.
- Ledger / leaderboard entries carry `scenarioKey`; cross-scenario rank is refused.

## Execution (D1)

Muse runs **Desktop/browser-only** via `museRuntimeClient` / `runUnderWorld` (+ `forecastFieldsUnderWorld` adapter onto ForecastHost `regime|auction|lattice`). Strategy source never uploads to `/world/*`.

See `JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`.
