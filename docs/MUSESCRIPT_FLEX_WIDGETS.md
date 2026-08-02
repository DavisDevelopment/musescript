# MuseScript FlexLayout widgets

User-authored **panel** and **on-chart** widgets.

## Source of truth (host)

- Design brainstorm: [`production_terminal_inspo/MUSESCRIPT_FLEX_WIDGETS.md`](../../../production_terminal_inspo/MUSESCRIPT_FLEX_WIDGETS.md)
- **Live authoring guide:** `kalshai/mobile/src/terminal/widgets/MUSESCRIPT_WIDGETS.md`
- Registry / runtime / New Widget UX: `kalshai/mobile/src/terminal/widgets/`
- Session bridge (Charts ↔ Terminal): `kalshai/mobile/src/terminal/session/`
- Examples:
  - [`../examples/widgets/hello_flex_widget.ms`](../examples/widgets/hello_flex_widget.ms) — standalone panel
  - [`../examples/widgets/hello_chart_widget.ms`](../examples/widgets/hello_chart_widget.ms) — on-chart SMA

## Placement

| `placement` | Where it shows |
|-------------|----------------|
| `panel` | FlexLayout dock (`ms:<id>`) in Terminal + Charts palette |
| `chart` | Advanced chart indicator menu (`MSW_<ID>`) only |
| `both` | Panel + chart |

## Surfaces

`pre` · `table` · `sparkline` · `html-safe` (allowlist sanitizer) · `canvas` (host 2d plot series)

## Marketplace + integrity

Publishing reuses Decision 6 durable `/social/publish` with `artifactKind: "widget"`.
Installing from the feed registers the manifest into the local widget library after **SHA-256 content-hash** verify plus optional **ed25519** signature verify against the package's embedded `publicKey` (invalid signatures refused; allowlist can mark `trusted`). See trust model in `MUSESCRIPT_WIDGETS.md`.

## Charts ↔ Terminal

`terminalRunSession` publishes Studio/Terminal run snapshots; Charts `SessionBoundPanel` mounts the same Truth/Evolve/Ledger/… modules against that store. MuseRuntime is preloaded from the Charts widget palette / panel host.

FlexLayout persistence key: `mederos.terminal.layout.v2` (bridges from `v1`).
