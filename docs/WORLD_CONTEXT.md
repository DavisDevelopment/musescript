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

- **calendar** (default when market bars provided): as-of join — fan sample with `t ≤ barSimDay` only (no lookahead).
- **timestep**: one Muse bar per `tDays[k]`; synthetic OHLCV labeled in tape meta.

## Execution (D1)

Muse runs **Desktop/browser-only** via `museRuntimeClient` / `runUnderWorld`. Strategy source never uploads to `/world/*`.

See `JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`.
