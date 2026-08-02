# MuseScript FlexLayout widgets

User-authored **panel** and **on-chart** widgets.

## Source of truth (host)

- Design brainstorm: [`production_terminal_inspo/MUSESCRIPT_FLEX_WIDGETS.md`](../../../production_terminal_inspo/MUSESCRIPT_FLEX_WIDGETS.md)
- **Live authoring guide:** `kalshai/mobile/src/terminal/widgets/MUSESCRIPT_WIDGETS.md`
- Registry / runtime / New Widget UX: `kalshai/mobile/src/terminal/widgets/`
- Examples:
  - [`../examples/widgets/hello_flex_widget.ms`](../examples/widgets/hello_flex_widget.ms) — standalone panel
  - [`../examples/widgets/hello_chart_widget.ms`](../examples/widgets/hello_chart_widget.ms) — on-chart SMA

## Placement

| `placement` | Where it shows |
|-------------|----------------|
| `panel` | FlexLayout dock (`ms:<id>`) in Terminal + Charts palette |
| `chart` | Advanced chart indicator menu (`MSW_<ID>`) only |
| `both` | Panel + chart |

## Marketplace

Publishing reuses Decision 6 durable `/social/publish` with `artifactKind: "widget"`.
Installing from the feed registers the manifest into the local widget library.

FlexLayout persistence key: `mederos.terminal.layout.v2` (bridges from `v1`).
