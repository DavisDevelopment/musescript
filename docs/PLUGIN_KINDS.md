# MuseScript plugin / widget kinds

Engine-level **capability surface** for non-strategy programs (FlexLayout
widgets, future app plugins). Full Studio / evo strategies are unaffected.

Source of truth: `musescript/types/PluginKind.hx` +
`musescript/types/PluginCapabilities.hx`.

Schema: `musescript.plugin-kinds/2` (adds `io_fs` / `io_net`).

## Kinds

| Kind | Allows | Notes |
|------|--------|-------|
| `compute` | read-only compute (bars, series, params, stats, ML, graph query, panel field reads, `muse.str` / `muse.path` / `muse.re`) | **default** for plugins |
| `chart` | compute + `plot` / `plotshape` / `hline` / `bgcolor` + `log` | on-chart overlays |
| `panel` | compute + chart draws + `log` | FlexLayout dock widgets |
| `scanner` | compute only today | reserved — `scan_top` / `scan_bottom` still denied until a real consumer lands |

## Always denied (every plugin kind)

- **Orders / portfolio mutate:** `long` `short` `flat` `close` `buy` `sell` `sell_all` `rebalance_equal` `target_weight` `orders_cancel_all` `portfolio_*`
- **Namespaced aliases:** `muse.orders.*` order verbs, `muse.portfolio.buy` / `sell_all` / apply mutants (lowered then audited)
- **`io_fs`:** `fs_*`, `db_*` (and `muse.fs.*` / future `muse.db.*` after lower) — even if a stub is installed
- **`io_net`:** `http_*` (and `muse.http.*` after lower)
- **Host escape hatches:** `Reflect` `eval` `Sys` `File`/`FileSystem` `Http` `fetch` `require` …

Compute-safe string/path/regex helpers (`str_*`, `path_*`, `re_*`, `muse.str.*`,
`muse.path.*`, `muse.re.*`) stay allowed. Filesystem / HTTP are grant-gated for
strategies and **always denied** for plugins — see `docs/MUSE_IO.md`
(backtest never silent-live HTTP; replay fixtures only).

## Host API (after `haxe build-runtime.hxml`)

```js
MuseRuntime.pluginKinds()                    // table JSON
MuseRuntime.checkWidget(source, { kind })    // audit only
MuseRuntime.runWidget(source, bars, { kind }) // audit then run (skipTruthReport default)
MuseRuntime.resolveIoGrants(opts)            // null unless opts.grants set
MuseRuntime.requireIoGrant(op, opts)         // throws IoDenied when grants null
MuseRuntime.run(src, bars, { grants })       // sandboxed muse.fs / muse.http when grants set
MuseRuntime.run(src, bars, { grants, http: "replay"|"record"|"strict"|"off" })
MuseRuntime.runIngest(src, { grants, http, kind: "ingest"|"cli" })  // CLI IO tier — not a plugin
```

Default `kind` for `checkWidget` / `runWidget` is **`panel`** (widgets need
plot + log). Pass `kind: "chart"` for overlay-only, `kind: "compute"` for
pure numeric plugins.

Interp entry: `MuseInterp.executePlugin(prog, kind)` — throws on violation.
Ingest is **not** a plugin kind — use `MuseRuntime.runIngest` /
`MuseInterp.executeIngest` with `FsGrant`/`NetGrant` (see `docs/MUSE_IO.md`).

Strategies / fitness: IO is **grant-gated** (`opts.grants` default null →
`IoDenied`; `fitness:true` forces grants null). Plugins never receive grants.
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
- `docs/MUSE_IO.md` — `muse.re` / `muse.fs` / `muse.http` + IoGrant
- `docs/MUSE_DIAG.md` — post-run `muse.diag` ACF / kiss-the-curve pack
- Examples: `examples/widgets/hello_flex_widget.ms`, `hello_chart_widget.ms`
