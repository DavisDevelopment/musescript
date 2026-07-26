# Chart binding — GeomViz → glcharts

The chart / website surface for this geometry stack lives in the sibling Mederos app:

`../../../../mobile/src/glcharts/geom/`

| Piece | Role |
|---|---|
| `contract.js` | JS mirror of `GeomViz.hx` slots + unpack helpers |
| `paint.js` | Canvas2D levels / rays / zones / pivots / labels / forecast / arcs / rings / cycle / ribbon |
| `live.js` | MuseRuntime last-bar packs → `frameFromPartial` (preferred path) |
| `synthesize.js` | Demo / fallback frames when live packs are missing; still owns arcs/rings/cycle/ribbon extras |
| `pack.js` | Registry: `GEOM_FIB`…`GEOM_RISK` gallery packs **and** per-builtin overlays (`fib_fan`, `gartley`, …) |

**Status coding:** Confirmed solid · Forming dashed · Projected dotted/ghost.

**Website spots:** live-demo widget Geometry stack slide (`npm run demo:dev` in `mobile/`),
Strategy Studio Indicator Library (+ **Add to chart** via `chartBridge` when Advanced is open),
Classic IndicatorPicker entries (Advanced-only notes), Advanced `+ ind` menu (packs + builtins).

## Live wiring (sibling ↔ chart)

Indicators nest `levels` / `rays` / `zones` / `pivots` / `labels` / `forecast`
(see `GeomVizSpec`). The chart:

1. Runs the matching MuseScript builtin over the tape (`geom/live.js`).
2. Plots pack slots on the **last bar only**, rebuilds a frame via `frameFromPartial`.
3. Falls back to `synthesize.js` only when packs are missing or MuseRuntime is cold.
4. Merges synth-only extras (`arcs` / `rings` / `cycle` / `ribbon`) onto live frames when present.
5. Keeps a scalar `mid` legend hook from primary level / forecast midpoint.

Family gallery cards map to a default live builtin (`FAMILY_LIVE_BUILTIN`); any listed
builtin id also resolves through `tryLiveGeomFrame(bars, id)` and is registered as its
own Advanced overlay id (picker → `addIndicator` → same GeomViz paint path).

## Live emitters (indicator → GeomViz fields)

Indicators that nest `levels` / `rays` / `zones` / `pivots` / `labels` / `forecast`
in their TObject output (chart drops synthesize when these packs are present):

| Family | Builtin / class | Nested packs |
|---|---|---|
| GEOM_FIB | fib_retracement, fib_extension, auto_fib, fib_projection, fib_fan, fib_channel, fib_arcs, fib_confluence, fib_time_zones, golden_pocket, murrey_math_lines | levels±zones±pivots±rays±forecast±arcs |
| GEOM_HARMONIC | gartley, bat, butterfly, crab, shark, cypher | levels, zones (PRZ), pivots, labels (XABCD) + `.signal` |
| GEOM_EW | ew_hypothesis | pivots, labels (waves), forecast, zones |
| GEOM_GANN | gann_angles, square_of_nine | levels, rays (gann), pivots, labels, rings (So9) |
| GEOM_CYCLES | ssa_cycles | zones (Cycle), forecast, labels |
| GEOM_RISK | lppl_warning | zones, forecast, labels |

Chart-only extras that remain synth-side until promoted: `cycle` series / `ribbon`
(SSA / LPPL full-tape overlays). `arcs` / `rings` are now first-class capped packs
(`ArcSet` / `RingBag` in GeomViz) emitted by `fib_arcs` and `square_of_nine`.
