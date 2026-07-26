# Chart binding — GeomViz → glcharts

The chart / website surface for this geometry stack lives in the sibling Mederos app:

`../../../../mobile/src/glcharts/geom/`

| Piece | Role |
|---|---|
| `contract.js` | JS mirror of `GeomViz.hx` slots + unpack helpers |
| `paint.js` | Canvas2D levels / rays / zones / pivots / labels / forecast / arcs / rings / cycle / ribbon |
| `live.js` | MuseRuntime last-bar packs → `frameFromPartial` (preferred path) |
| `synthesize.js` | Demo / fallback frames when live packs are missing; still owns arcs/rings/cycle/ribbon extras |
| `pack.js` | Registry ids `GEOM_FIB` … `GEOM_RISK` (gallery + Indicator Library) |

**Status coding:** Confirmed solid · Forming dashed · Projected dotted/ghost.

**Website spots:** live-demo widget Geometry stack slide (`npm run demo:dev` in `mobile/`),
Strategy Studio Indicator Library categories, Classic IndicatorPicker entries (paint on Advanced).

## Live wiring (sibling ↔ chart)

Indicators nest `levels` / `rays` / `zones` / `pivots` / `labels` / `forecast`
(see `GeomVizSpec`). The chart:

1. Runs the matching MuseScript builtin over the tape (`geom/live.js`).
2. Plots pack slots on the **last bar only**, rebuilds a frame via `frameFromPartial`.
3. Falls back to `synthesize.js` only when packs are missing or MuseRuntime is cold.
4. Keeps a scalar `mid` legend hook from primary level / forecast midpoint.

Family gallery cards map to a default live builtin (`FAMILY_LIVE_BUILTIN`); any listed
builtin id also resolves through `tryLiveGeomFrame(bars, id)`.

## Live emitters (indicator → GeomViz fields)

Indicators that nest `levels` / `rays` / `zones` / `pivots` / `labels` / `forecast`
in their TObject output (chart drops synthesize when these packs are present):

| Family | Builtin / class | Nested packs |
|---|---|---|
| GEOM_FIB | fib_retracement, fib_extension, auto_fib, fib_projection, fib_fan, fib_channel, fib_arcs, fib_confluence, fib_time_zones, golden_pocket, murrey_math_lines | levels±zones±pivots±rays±forecast |
| GEOM_HARMONIC | gartley, bat, butterfly, crab, shark, cypher | levels, zones (PRZ), pivots, labels (XABCD) + `.signal` |
| GEOM_EW | ew_hypothesis | pivots, labels (waves), forecast, zones |
| GEOM_GANN | gann_angles, square_of_nine | levels, rays (gann), pivots, labels |
| GEOM_CYCLES | ssa_cycles | zones (Cycle), forecast, labels |
| GEOM_RISK | lppl_warning | zones, forecast, labels |

Still synth-only on chart: `arcs` / `rings` / `cycle` series / `ribbon` array extras
in `emptyFrame()` until promoted into GeomViz.hx (FibArcs/So9/SSA/LPPL already paint via
levels/zones/forecast; extras are optional polish).
