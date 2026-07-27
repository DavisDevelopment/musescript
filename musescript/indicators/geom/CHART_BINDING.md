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
4. Merges synth extras onto live frames only when the live pack omit that slot
   (`arcs` / `rings` / `cycle` / `ribbon`).
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
| GEOM_EW | ew_hypothesis | pivots, labels (waves), forecast, zones (+ ParentDegree when nested) |
| GEOM_GANN | gann_angles, square_of_nine | levels, rays (gann), pivots, labels, rings (So9) |
| GEOM_CYCLES | ssa_cycles | zones (Cycle), forecast, labels, cycle (CycleSeries) |
| GEOM_RISK | lppl_warning | zones, forecast, labels, ribbon (RibbonSeries) |

### EW parent degree overlay (C11)

`ew_hypothesis` scalars (also plotted live → `frame.parent`):

| Scalar | Meaning |
|---|---|
| `degree` | 0 = fine / inner, 1 = coarse / outer |
| `parentLabelCode` | Coarse pattern: 0 none, 1 zigzag, 2 impulse5, 3 flat*, 4 diagonal, 5 triangle, 6 double_zigzag |
| `nestScore` | Soft nesting multiplier (1.0 = neutral) |
| `parentStartBar` / `parentEndBar` | Coarse parent bar span |

Pack convention (no Cap bump — reuses `zones[]` / `labels[]` slots):

- `ZoneKind.ParentDegree` (11) — coarse price×bar box; status **Forming** (dashed / lower opacity)
- Label with `Impulse` (50) or `Zigzag` (51) + Forming — parent pattern glyph behind fine Wave1–5 / A–C
- `ZoneKind.Invalidation` (10) reserved for B7 count-kill bands (sibling)

Chart toggle: `theme.geom.parentOverlay` (default `true`). When false, ParentDegree zones and Impulse/Zigzag Forming labels are skipped.

Chart-only extras that remain synth-side until promoted: none for the
ArcSet / RingBag / CycleSeries / RibbonSeries family — those are first-class
capped packs emitted by `fib_arcs`, `square_of_nine`, `ssa_cycles`, and
`lppl_warning`. Full-tape `values[]` arrays stay optional synth fallbacks only.
