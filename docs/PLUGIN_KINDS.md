# MuseScript plugin / widget kinds

Engine-level **capability surface** for non-strategy programs (FlexLayout
widgets, future app plugins). Full Studio / evo strategies are unaffected.

Source of truth: `musescript/types/PluginKind.hx` +
`musescript/types/PluginCapabilities.hx`.

## Kinds

| Kind | Allows | Notes |
|------|--------|-------|
| `compute` | read-only compute (bars, series, params, stats, ML, graph query, panel field reads) | **default** for plugins |
| `chart` | compute + `plot` / `plotshape` / `hline` / `bgcolor` + `log` | on-chart overlays |
| `panel` | compute + chart draws + `log` | FlexLayout dock widgets |
| `scanner` | compute only today | reserved — `scan_top` / `scan_bottom` still denied until a real consumer lands |

## Always denied (every plugin kind)

- **Orders / portfolio mutate:** `long` `short` `flat` `close` `buy` `sell` `sell_all` `rebalance_equal` `target_weight` `orders_cancel_all` `portfolio_*`
- **Namespaced aliases:** `muse.orders.*` order verbs, `muse.portfolio.buy` / `sell_all` / apply mutants (lowered then audited)
- **IO / escape hatches:** `Reflect` `eval` `Sys` `File`/`FileSystem` `Http` `fetch` `require` …

## Host API (after `haxe build-runtime.hxml`)

```js
MuseRuntime.pluginKinds()                    // table JSON
MuseRuntime.checkWidget(source, { kind })    // audit only
MuseRuntime.runWidget(source, bars, { kind }) // audit then run (skipTruthReport default)
```

Default `kind` for `checkWidget` / `runWidget` is **`panel`** (widgets need
plot + log). Pass `kind: "chart"` for overlay-only, `kind: "compute"` for
pure numeric plugins.

Interp entry: `MuseInterp.executePlugin(prog, kind)` — throws on violation.

## Mobile migration (regex → engine)

Today `mobile/src/terminal/widgets/museWidgetRuntime.js` uses a host regex
denylist (`long(`/`short(`/…). Switch to:

```js
const gate = MuseRuntime.checkWidget(source, { kind: placement === "chart" ? "chart" : "panel" });
if (!gate.ok) return { ok: false, error: gate.error, … };

// or one shot:
MuseRuntime.runWidget(source, tape, { kind, instrument: true, tier: "js", skipTruthReport: true });
```

Requires a rebuilt/synced `muse-runtime.js` (and web vendor copy) before
dropping the regex — keep the regex as a temporary belt until the runtime
with `runWidget` is deployed, then remove it.

## Docs pointers

- ROADMAP §6 Plugin/extension programs
- `docs/MUSESCRIPT_FLEX_WIDGETS.md`
- Examples: `examples/widgets/hello_flex_widget.ms`, `hello_chart_widget.ms`
