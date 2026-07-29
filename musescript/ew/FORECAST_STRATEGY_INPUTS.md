# Forecast-aware strategies (Initiative 3.3)

Strategies (authored or evolved) can read forecast-host reductions as first-class
inputs. The co-evolution boundary already maps every `EwForecastHost` cloud through
`ProjectionProvider.cloudField` into the shared `SProj` vocabulary.

## Reduction vocabulary

| Field | Aliases | Meaning |
|-------|---------|---------|
| `p50` | `mean`, `poc` | Price mid (auction POC) |
| `p05` / `p95` | | Lower / upper price band |
| `spread` | | Band width |
| `prob_up` | `breakout_prob` | P(up) / auction discovery-up mass |
| `entropy` | | Count / regime ambiguity (high = uncertain) |
| `inv` | | Invalidation price (lattice; often NaN on regime/auction) |
| `dist_inv` | | Distance to invalidation |
| `top_mass` | | Posterior mass on preferred count |
| `nest` | | Soft nest score across degrees |
| `label` | | Opaque label code for viz |

Hosts: `lattice`, `regime`, `auction`, `mcmc`.

## Evo / genome usage

```
SProj("ew_0", "entropy")
SProj("ew_0", "breakout_prob")   // alias → prob_up
SProj("ew_0", "inv")
```

Seed genomes: `CorpusSeed` host seeds (`--ew-host`). Provider: `Fitness.projectionProvider`
+ `ProjectionProvider.decorateBars` writes `Expand.projRef(name, field)` aux columns.

## Studio / MuseScript

Product shorthand `forecast("regime").entropy` means: bind a regime host projection
named e.g. `ew_0`, then read field `entropy`.

Runtime introspection:

```js
MuseRuntime.forecastFields()
// → { ok, fields:[{field,aliases,note}…], hosts, usage }
```

Full chart overlay UI is Initiative 2; this doc wires the reduction hooks for
optimizer / authored strategies.
