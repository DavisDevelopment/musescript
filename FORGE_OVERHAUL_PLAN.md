# Forge Overhaul Plan — Premium No-Code Trading Programming

> **Status:** Phase 0 + Phase 1 vertical slice **shipped** (2026-08-04); Phase 2
> (palette + Logic Lane materialization + richer `@on(bar)` + canvas UX) **landed in
> code** (2026-08-04); Phase **3.1** chart-native tape stage + S polish **landed**
> (2026-08-05); Phase **3.2** Prove latch + **3.3** Optimize/Autoresearch deep-link
> **landed** (2026-08-05); Phase **4** Artifacts / Swarm / Marketplace / WASM+Forge seed
> **landed** (2026-08-05). MuseLab / Studio Blueprints.
> Distill Forge UI **not** rewritten (Distill-only + → Blueprints importer handoff).
> **Home for Forge / Blueprints next-gen work.** Web vendoring / surface parity stays in
> [`WEB_SURFACE_PARITY_PLAN.md`](./WEB_SURFACE_PARITY_PLAN.md); Forge *product*
> overhaul + Blueprints IDE placement is tracked here.
>
> **Primary source of truth (Distill Forge UI):** `kalshai/mobile/src/lab/forge/`  
> **Web host (Distill Forge):** `mederos-web` `/app/forge` via `ForgeHost` + vendored copies  
> **Blueprints IDE home (locked):** MuseLab Panel / Studio — **not** `/app/forge`  
> **Blueprints impl:** `kalshai/mobile/src/lab/blueprints/` (`@xyflow/react` + custom chrome)  
> **Engine:** this repo (`musescript/`) — MuseRuntime, palette, evo, Truth Report, plugins

Companion planning (partially shipped / partially aspirational; do not treat as current ship truth):

- `kalshai/mobile/FORGE_PLAN.md` — v1 shipped status + deferred §9
- `kalshai/ai_md/FORGE_STRATEGILAB_MUSESCRIPT_PLAN.md` — Muse IR cutover thesis (2026-07-15)
- `mederos-web/src/mobile/lab/VENDOR.md` — what is actually on `/app/forge` today

---

## Decisions locked (2026-08-04)

| # | Decision | Locked choice |
|---|---|---|
| 1 | **Canonical IR** | **Muse Blueprints** — Distill boolean becomes **import** into Blueprints **Logic Lane** (not forever-canonical save) |
| 2 | **Prove latch** | Truth Report required **only before Marketplace publish / live deploy** — **not** on every Library / Swarm save |
| 3 | **Home surface** | Keep **Forge Distill-only** (`/app/forge` + mobile Forge tab). Expand **MuseLab / Studio** into the Blueprints IDE. Do **not** grow `/app/forge` into Blueprints |
| 4 | **Graph renderer** | **Hybrid** — mature library for pan / zoom / layout; **custom node chrome** for brand |
| 5 | **Graph library** | **`@xyflow/react` (React Flow / xyflow)** — pan / zoom / layout; Muse branded node chrome on top |

### Surface implications (rewrite of earlier open forks)

- **Blueprints lives in MuseLab Panel / Studio** (or a MuseLab “Blueprints” mode), not as a Forge page rewrite.
- **Forge remains** the Distill boolean whiteboard and becomes an **importer / exporter** into Blueprints Logic Lane (`forgeGraph` → Muse boolean subgraph / Logic Lane nodes).
- **Save policy:** Library / Swarm saves may stay light (valid Muse / distill AST + provenance). **Prove / Truth Report** is the physical latch on **publish & live deploy** only — soften any “block every Save until Truth passes” wording.
- **Phase 0 / 1** scaffold the MuseLab / Studio Blueprints editor; they do **not** replace `/app/forge`.
- **Renderer:** Blueprints canvas uses `@xyflow/react`; Distill Forge may keep hand-rolled SVG until a later optional polish.

---

## 1. Current Forge — inventory

### 1.1 What the page is today (product terms)

Forge is a **visual editor for distill-rule boolean trade logic**, not a general
MuseScript / strategy authoring IDE. Under the locked home-surface decision,
that Distill scope is **intentional and durable**: Forge stays Distill-only;
full Muse Blueprints land in MuseLab / Studio.

Product promise as shipped:

- Take the same boolean AST DistillBench edits as text (`Cmp` / `Not` / `Bin`) and
  draw it as a **draggable node graph**.
- Live **held-out scoring** and optional OOS backtest chart when seeded with a
  distilled agent.
- Optional **on-device LLM propose → canvas diff → accept/reject/iterate**
  (Composer loop) — gated; web is honest **manual mode**.
- Save as a **library rule** or write back to a **Swarm node** — Forge is a
  candidate *source*, not a bypass of the promotion gate.

Stated marketing copy on web (`ForgeHost.tsx`): “Indicator & logic forge — Build
trade logic visually, evaluate it against real feature matrices, and send it back
to the swarm or the library.”

Honest product gap vs that sentence: the live Forge Page still edits the
**distill boolean grammar**, evaluates against **agent feature frames** (not full
MuseScript strategy bars), and does **not** yet author full `@on(bar)` strategies
with sizing, stops, panels, or Truth-Report-gated optimize. Closing that gap is
**MuseLab / Studio Blueprints work**, not a Forge page rewrite.

### 1.2 UI structure (panels, flows, tech)

| Layer | What |
|---|---|
| **Mobile tab** | `OperatorConsole.jsx` → lazy `FULL_VIEWS.Forge` → `ForgePage.jsx` |
| **Web route** | `/app/forge` → `ForgeHost.tsx` → dynamic import vendored `ForgePage.jsx` (SSR off) |
| **Shell** | Header (back + title + Graph/Text mode seg) · main stage · right **rail** |
| **Stage** | Empty state with 3 starter templates · **SVG canvas** (`ForgeCanvas`) · or text rule editor |
| **Rail** | Node inspector · live bacc/agree · backtest CTA / OosHeroChart · Ask AI · Indicators panel · Save |
| **Review mode** | Replaces stage+rail with proposal canvas + accept/reject/iterate |

**Tech stack (verified):**

- **React** JSX (plain CSS theme tokens; web wraps in dark chrome `#16171d`).
- **Hand-rolled SVG** canvas — deliberately **no** React Flow / xyflow dependency
  (`FORGE_PLAN.md` §3.2: zero new deps for v1). Blueprints hybrid renderer
  (library + custom chrome) applies to **MuseLab / Studio**, not a mandate to
  rip Forge’s Distill canvas on day one.
- **Scoring:** `python/pyRouter.js` → Pyodide `mobile_distill.score_rule` /
  `backtest_rule` for pure-feature rules; **JS-exact** `scoreRuleWithIndicators`
  when form-op indicators are present.
- **LLM:** `forgeLlm.js` → `onDeviceLlm` / `llmClient` seams. Web: unavailable →
  Composer stays off (`ForgeHost` comments this honestly).
- **Seed handoff (web):** `sessionStorage` key `mederos.web.forgeSeed` from Lab /
  Swarm inspectors.

**Entry points that seed Forge today:**

- DistillBench — “edit visually in Forge”
- SwarmNodeInspector / SwarmContextMenu
- Strategy Library / CodeCard retarget
- Blank Forge tab (no agent → no live score)

### 1.3 What you can actually do (capabilities + limits)

**You can:**

- Build / edit boolean formulas: `(feature > c)` / `<`, `∧` / `∨`, inline `¬`.
- Flip Graph ↔ Text with live parse (`parseRule` / `pretty` from `distillEngine.js`).
- Grow trees (`+AND` / `+OR`), retarget features/constants, delete with sibling promote.
- Use **shared form-op indicators** (sma/ema/momentum/roc/zscore/std/rollmax/rollmin/slope)
  as extra terminal names; retune window.
- Score against held-out frames when an agent seed is present; backtest OOS NAV
  (non-indicator rules).
- Accept tree/pipeline seeds via **lossy projection** to boolean (`treeProjection.js`);
  save converts Swarm tree/pipeline nodes to beam (explicit confirm).
- Project Forge → MuseScript **boolean fragment** (`forgeMuseProjection.js` →
  `@param` + `if (expr) long();`) — used in selftests / integration seams, **not**
  the live save path of ForgePage.
- View richer Muse `@on(bar)` ASTs as graphs in **MuseLabPanel** (server `/muse/ast`
  + `tradeLogicGraph.js`) — **read-mostly**, not the ForgePage edit loop. This
  panel is the **natural vertical-slice host** for Blueprints editing.

**You cannot (honest limits):**

| Limit | Reality in code |
|---|---|
| Full MuseScript strategies on the Forge tab | ForgePage stays on Cmp/Bin; `tradeLogicGraph` is parallel + MuseLab-only — **by plan, Forge stays Distill** |
| Drag-to-connect rewiring | Canvas is select + move; structural edits are rail-only |
| Arithmetic / if / for / orders as editable Forge v1 | Render kinds exist in `ForgeCanvas.KIND`; editing UI does not |
| Indicator → Pyodide backtest parity | Documented JS-only scoring path |
| Round-trip Muse AST → forgeable boolean losslessly | `museAstToForgeGraph` rejects unsupported; reverse needs typed JSON service |
| On-web LLM Composer | Stubbed / ready=false |
| Truth Report / optimize / evolve from Forge | Those live in StrategyStudio panels — Blueprints Prove latch deep-links here |
| Marketplace publish of Forge graphs | Saves library rule AST — widget publish path is separate (`NewMuseWidgetModal`); Blueprints publish adds Truth latch |

### 1.4 File map (key modules)

**Mobile (canonical Distill Forge):** `kalshai/mobile/src/lab/forge/`

| File | Role |
|---|---|
| `ForgePage.jsx` | Page shell, score/backtest, Composer, save, IndicatorPanel, NodeInspector |
| `ForgeCanvas.jsx` | SVG view + selection + drag-move; KIND map includes tradeLogic kinds |
| `forgeGraph.js` | Boolean AST ↔ graph; validate; layout; edit helpers |
| `tradeLogicGraph.js` | **Additive** MuseAstJson → graph (if/for/call/order/…) — not ForgePage source of truth; **Blueprints graph seed** |
| `forgeMuseProjection.js` | Graph → Muse expr / `.ms` fragment — Forge → Logic Lane export path |
| `museAstToForgeGraph.js` | Muse cond JSON → Forge boolean graph (reject-hard) |
| `treeProjection.js` | CART/pipeline → boolean OR-of-LONG-paths |
| `forgeIndicators.js` + `indicatorStore.js` | Form-op terminal factories + library |
| `forgeLlm.js` + `forgeDiff.js` | Propose + expression-set diff |
| `*.selftest.js` | Pure node selftests (graph, indicators, projection, tradeLogic) |

**Web:**

| Path | Role |
|---|---|
| `mederos-web/src/app/app/forge/page.tsx` | Distill Forge route (stays Distill) |
| `mederos-web/src/components/forge/ForgeHost.tsx` | Host chrome + seed + nav |
| `mederos-web/src/mobile/lab/forge/**` | Vendored (sync from mobile; do not edit in-place) |

**Related consumers (Blueprints home):**

- `MuseLabPanel.jsx` — Muse source + ForgeCanvas of `astJsonToGraph(onBar.body)` → **expand into Blueprints IDE**
- StrategyStudio panels — Optimize / Autoresearch / Truth / Report Card / Ledger
- `DistillBench.jsx`, `swarmStore.js` (`saveForgeEditToNode`)
- `charting/indicators/userIndicator.js` — reuses forge form-ops

---

## 2. Surrounding infrastructure stocktake

### 2.1 MuseScript language affordances a no-code tool should emit

Blueprints (MuseLab / Studio) should **lower to** MuseScript (not invent a third
strategy IR). The engine already has the surfaces visuals should target:

| Affordance | Where | Why Blueprints / Forge care |
|---|---|---|
| Strategy / module / param / `@on(bar)` | `StrategyParser.hx`, sample in `MuseLabPanel` | Canonical executable unit |
| Orders | `long` / `short` / `flat` / portfolio verbs | Action sinks beyond boolean TRADE SIGNAL |
| Series builtins + TA | `BuiltinSigs.hx` palette (`sma`, `crossover`, …) | Typed node palettes, not ad-hoc feature strings |
| Expr + **stmt templates** | `TemplateExpand.hx` | Macros as reusable graph “blocks” / genes |
| Macros / pipelines | Parser surface + decls | Distill pipelines → typed MS instead of boolean projection |
| Plugin kinds | `PluginCapabilities.hx` + `MuseRuntime.pluginKinds()` | Chart/panel/compute capability gates for authored widgets |
| Panel / portfolio | `runPanel`, `PortfolioBuiltins`, evo panel genomes | Multi-name no-code without fake N×single runs |
| NP / PD (gated) | evo README + `VmNpEligibility` / WASM PD honesty | Advanced nodes only when runtime can actually run them |
| WASM / JS / interp tiers | `MuseRuntime.run` / `emitWat` / `runWasm` | Deterministic run + marketplace artifact story |
| Optimize / evolve | `MuseRuntime.optimize` / `evolve` | Same AST Blueprints edits should be searchable |
| Truth / Report Card / Ledger | `evaluateTruthReport`, `buildReportCard`, `ledgerEntryFromTruth` | Quant-honest latch on **publish / live deploy** |
| Widgets | `checkWidget` / `runWidget` | Visual authoring of terminal panels, not only strategies |
| Forecast fields | `forecastFields`, ForecastHostRuntime | Overlay vocabulary for chart-native nodes |

**Already-built projection bridges (honest scope):**

- Boolean Forge → Muse fragment: `forgeMuseProjection.js` (real, narrow) — **export seam into Logic Lane**.
- Muse full AST → tradeLogic graph: `tradeLogicGraph.js` + `/muse/ast` (view path in MuseLab).
- Muse cond → boolean Forge: `museAstToForgeGraph.js` (subset, reject-hard).
- Missing piece called out in code: server AST JSON for **full** Blueprints↔Muse
  round-trip editing (`forgeMuseProjection` header).

### 2.2 Surfaces Blueprints / Forge should compose with (not reinvent)

| Surface | Path | Composition role |
|---|---|---|
| **Forge (Distill-only)** | `/app/forge`, `ForgePage.jsx` | Boolean whiteboard; import/export to Blueprints Logic Lane |
| **DistillBench** | `lab/DistillBench.jsx` | Distill → seed Forge; keep shared score/save gate |
| **FitArena / FanChartTheater** | StrategyLab tabs | Fit/sim theater stays Lab; consume agents/rules |
| **StrategyStudio** | Optimize, Autoresearch, Debugger, Truth, Report Card, Ledger | Post-author rigor; Blueprints **Prove** deep-links here on publish/deploy |
| **Indicator Library** | Studio + forgeIndicators | Unify form-ops → typed Muse indicator decls |
| **MuseLabPanel / Studio** | Validate / backtest / artifact / view-as-graph | **Primary Blueprints IDE home** (locked) |
| **Widgets / New widget** | `WidgetPalette` + `NewMuseWidgetModal` | Template + capability audit + marketplace publish precedent |
| **Swarm** | graphs, `saveForgeEditToNode` | Ensemble slots should point at Muse artifact IDs; light Library/Swarm save OK |
| **Marketplace / social** | `StrategyFeed`, widget publish | Share Blueprints-authored MS + Truth receipts; **Prove latch required** |
| **Charts / Terminal** | GlChart, Instrument Terminal modules | Live preview panes; Blueprints should feel chart-native |
| **gene-runner / MuseGene** | `musescript/evo/*`, gene-runner JS | Same templates as palette nodes + evolve off canvas |

### 2.3 Engine APIs — in-browser vs dataserver/relay

**In-browser today (web + mobile):**

- `MuseRuntime` via `museRuntimeClient` / script-tag hashed public bundles:
  `run`, `check`, `runPanel`, `proveDeterminism`, `evaluateTruthReport`,
  `optimize`/`evolve`, Report Card / ledger helpers, `checkWidget`/`runWidget`,
  debug session, events catalog, pluginKinds.
- Distill JS-exact + optional Pyodide worker (`pyRouter`).
- ForecastHostRuntime (synced per web parity Phase 0).
- Local library / localStorage / IDB-ish paths; paper broker analogues on web.

**Dataserver / full PC node (`/muse/*`):**

- Capabilities, validate, compile/artifact register, buffered runs, **`/muse/ast`**
  for typed AST JSON — required for MuseLab graph view / Blueprints round-trip.
- Slim Electron sidecar **does not** register these → MuseLab degrades: local
  validate/backtest; graph/artifact disabled with honest reason.

**Relay / durable (web):**

- Auth, market bars, durable social/economy/paper (Decision 6 in parity plan).
- Not a strategy compiler; hosting for publish + tape, not gene search.

**Implication for Blueprints:** author + score + browser-tier run should work
**offline/browser-first**; heavy evolve/compile/artifact registry remain optional
upgrade when full `/muse` is present — never pretend they are local if they are
not. Truth Report is always available for Prove; **blocking latch** only on
Marketplace publish / live deploy.

---

## 3. Competitive / product bar

### 3.1 What “most powerful premium no-code for trading programming” means here

Not Bubble / Zapier. The bar is the intersection of:

1. **TradingView Pine visuals** — chart-native series, overlays, signal markers,
   params as knobs; everything feels like it belongs on a tape.
2. **Unreal Blueprints–grade graph power** — typed sockets, execution flow,
   compound macros, honest “this node is unsupported / runtime fallback” — not
   toy AND/OR trees pretending to be strategies.
3. **Quant-honest gates** — purge/embargo OOS, DSR/PBO/min-trades, seed
   robustness, determinism digests — **Marketplace publish / live deploy** blocked
   until Truth Report passes (differentiation vs “pretty nodes that overfit”),
   without taxing every Library/Swarm save.

### 3.2 Concrete UX metaphors (name them in UI copy + IA)

| Metaphor | Meaning |
|---|---|
| **Blueprint** | Typed Muse node graph in MuseLab / Studio; wires are Series / Scalar / Bool / Void / Panel |
| **Logic Lane** | Distill boolean subgraph (or projected view) inside Blueprints; Forge imports/exports here |
| **Tape stage** | Center composition: candles + overlays produced by the graph |
| **Macro shelf** | Stmt/expr templates + marketplace blocks as snap-in compounds |
| **Signal sink** | Explicit order / alert / widget emit nodes (not a vague “TRADE”) |
| **Honest gate** | Truth Report latch before **Marketplace publish / live deploy** (not every Library/Swarm save) |
| **Diff review** | Composer accept loop — keep on Forge; extend to Muse AST diffs in Blueprints |
| **Artifact** | Versioned MS source + optional WASM; Swarm/Library hold refs |
| **Lab relay** | Distill/evolve results land as editable Blueprints (via Logic Lane), not dead text |

Anti-goals: generic purple SaaS dashboard of cards; “AI wrote a strategy” with no
OOS at publish; silent flattening of unsupported Muse constructs into boolean trees;
growing `/app/forge` into a second Blueprints IDE.

---

## 4. Target architecture

### 4.1 Visual programming model — locked

Earlier options (boolean-only bolt-on, spreadsheet hybrid, timeline, Scratch blocks)
remain historical alternatives. **Locked north star: Muse Blueprints (Option B)**
with Distill boolean as **importer → Logic Lane**, not forever-canonical save.

| Locked piece | Choice |
|---|---|
| Canonical editor IR | Muse Blueprints → typed Muse AST / `.ms` |
| Distill boolean role | Import from Forge / DistillBench into **Logic Lane**; export back when a Swarm/beam slot still wants boolean |
| Graph editor host | **MuseLab Panel / Studio** (Blueprints mode) |
| Forge (`/app/forge`) | Stays Distill boolean whiteboard + importer/exporter |
| Graph rendering | **Hybrid:** `@xyflow/react` for pan / zoom / layout; custom Muse node chrome |
| Typed legality | Always Muse checker / sockets from `BuiltinSigs` — never owned by the UI kit |

Forge v1’s hand-rolled SVG may remain for Distill until a later optional polish;
Blueprints `@xyflow/react` host is the Phase 0/1 investment on the MuseLab surface.

### 4.2 How visuals lower to MuseScript

```
Forge Distill graph ──import/export──► Blueprints Logic Lane
                                              │
MuseLab / Studio Blueprints (graph + layout + provenance IDs)
        │  graphToMuseAst / graphToSource
        ▼
Typed Muse AST / source (.ms)
        │  MuseRuntime.check · TemplateExpand · PluginCapabilities
        ▼
Runnable artifact (interp | js | wasm) + optional Truth Report preview
        │
        ├── Library / Swarm refs (artifact id + source hash)  ← light save OK
        ├── Marketplace publish / live deploy                ← Prove latch REQUIRED
        └── Optimize/Evolve/Autoresearch (same AST, not a fork)
```

Rules:

1. **Blueprints graph is a projection of Muse AST**, not a parallel format (same
   discipline Forge v1 held for distill AST — raise the IR, keep the discipline).
2. Unsupported constructs → **read-only ghost + Open in Studio code**, never quiet
   rewrite (treeProjection’s convert warning is the pattern to generalize).
3. Indicators become Muse series/templates over time; Distill form-ops may remain
   on Forge until Logic Lane parity is green.
4. Palette, sockets, and legal edges generated from `BuiltinSigs` /
   `PluginCapabilities` / template decls — one schema with MuseGene.
5. Publish packages: source + params schema + **Truth receipt** + optional WASM.
6. Library / Swarm save: valid Muse (or Distill boolean for Forge) + provenance;
   Truth Report is **available**, not **required**.

### 4.3 Premium UI principles (for Blueprints in MuseLab / Studio)

Respect the user’s frontend design rules — **one composition**, brand-first,
no generic AI-purple dashboard:

- **One composition:** first viewport = brand-level **Blueprints / MuseLab** stage
  signal + tape + one CTA cluster (Run / Prove / Publish). No stat strips or card
  grids in the hero.
- **Brand:** Blueprints / MuseLab as hero-level wordmark in stage chrome — Forge
  keeps its own Distill hero on `/app/forge` (do not merge brand identities).
- **Atmosphere:** market microstructure feel — depth/tape gradients, precision
  mono for numbers, restrained accent (signal green / warn amber). Avoid purple
  glow, cream-serif cliché, broadsheet density.
- **Cards:** none in the hero; inspector uses denser inspector panels only when
  interaction needs a container.
- **Motion:** 2–3 intentional motions — wire pulse on valid type-connect, Truth
  latch close on publish, proposal diff morph — not confetti.
- **Density:** Blueprints density on desktop; one-rail inspector on mobile.
- **Renderer:** `@xyflow/react` handles viewport; **custom Muse node chrome** carries
  brand — do not ship stock xyflow theme skins as product UI.
- **Forge web host:** may stay framed Distill chrome; Blueprints graduates
  MuseLab / Studio toward a full-bleed canvas without rewriting ForgeHost.

---

## 5. Phased roadmap

Effort: **S** ≤ 1 day · **M** = 2–4 days · **L** = 1–2+ weeks.  
DoD = definition of done for that phase.

**Home for Phases 0–1:** MuseLab Panel / Studio Blueprints scaffolding — **not**
`/app/forge` replacement. Forge Distill continues in parallel as importer/exporter.

### Phase 0 — Contract lock + MuseLab Blueprints scaffolding (M)

**Status:** ✅ Done (2026-08-04)

**DoD**

- [x] Written schema: `BlueprintDocument` = Muse source + typed AST JSON + layout map +
  provenance (seed method, parent artifact hash, optional Logic Lane distill AST).
  → `mobile/src/lab/blueprints/blueprintDocument.js`
- [x] Enumerate Muse node kinds editable vs view-only vs Studio-only.
  → `museNodeKinds.js`
- [x] Spike hybrid graph renderer (`@xyflow/react` pan/zoom/layout + custom Muse node
  chrome) inside **MuseLab / Studio**; Distill Forge SVG may stay.
  → `BlueprintsCanvas.jsx` + `BlueprintNode.jsx`
- [x] Align Distill boolean as first-class **importer** into Logic Lane (Forge export
  via `forgeMuseProjection` / shared graph helpers), not forever-canonical Blueprints save.
  → `logicLaneImport.js` (Phase 1 stub; **Phase 2 materializes** typed Lane nodes)
- [x] Document Prove latch policy: Truth Report **required** only for Marketplace
  publish / live deploy; Library / Swarm save remain unblocked by Truth.
  → `proveLatchRequired()` + editor Save / Prove copy

**Deps:** none · **Effort:** M

### Phase 1 — MuseLab / Studio Blueprints vertical slice (L)

**Status:** ✅ Vertical slice landed (2026-08-04)

**DoD**

- [x] MuseLab Panel (or Studio “Blueprints” mode) **edits** a small `@on(bar)` subset:
  params, sma/crossover/ident/binop/if, `long`/`flat` — not a ForgePage rewrite.
  → MuseLab Code/Blueprints toggle; Studio mode seg **Blueprints**
- [x] Round-trip graph ↔ source through checker; selftests + 3 golden `.ms` files.
  → `museLower.js` / `museLift.js` + `blueprints.selftest.js` + `goldens/*.ms`
- [x] In-browser `MuseRuntime.run` on synth or last-tape bars; show trades + optional
  Truth **preview** strip (non-blocking for local/Library saves).
- [x] Distill boolean from Forge still opens in **Logic Lane** without breaking Swarm
  save; Forge `/app/forge` remains Distill-only.
- [x] Hybrid renderer wired for Blueprints canvas (`@xyflow/react` viewport + branded Muse nodes).

**Deps:** Phase 0; browser muse-runtime present (already) · **Effort:** L

### Phase 2 — Palette from engine + templates shelf (M–L)

**Status:** ✅ Landed in code (2026-08-04) — Logic Lane materialization + curated
BuiltinSigs palette + richer `@on(bar)` + canvas UX. Full live `pluginKinds` /
engine TemplateExpand compounds remain deferred polish under this phase’s spirit.

**DoD**

- [x] Node palette generated from `BuiltinSigs`-shaped JSON (filtered strategy mode;
  widget filter stub). → `blueprintPalette.js` (`STRATEGY_PALETTE_JSON`)
- [x] Stmt/expr template macros appear as compound nodes; expand via graph recipes
  (MA cross / RSI rising / thresh). Engine TemplateExpand deep-link = later.
- [x] Form-op indicators path toward Muse templates; Distill/Forge indicator scoring
  can remain until Logic Lane parity closed.
- [x] Full Distill → Logic Lane import materializes Cmp/Bin as typed Blueprints nodes
  (not parked fragment stub); Distill AST kept in provenance; export-back available.
  → `logicLaneImport.js` + Forge **→ Blueprints** stash handoff
- [x] Richer editable `@on(bar)` subset: ema/rsi/atr, comparisons, and/or, rising/falling, unop
- [x] Premium canvas UX: palette rail, Muse edges, selection inspector, undo; Emit + Run intact;
  Truth preview non-blocking; Marketplace latch still publish-only copy
- [x] Goldens `04_rsi_rising.ms` / `05_ema_atr.ms` + `blueprints.selftest.js` green

**Deps:** Phase 1 · **Effort:** M–L

### Phase 3 — Chart-native stage + Prove latch (publish/deploy) (L)

Split for ship cadence:

#### Phase 3.1 — Chart-native tape stage (+ S polish) ✅ (2026-08-05)

**DoD**

- [x] Center Blueprints stage embeds GlChart tape driven by Run: densified `chart[]`
  series overlays (or derived sma/ema preview when chart empty) + long/flat/short
  fill markers + equity spark. → `BlueprintsTapeStage.jsx` / `blueprintTape.js`
- [x] Truth preview strip: verdict + key gates (not raw JSON); non-blocking for
  Library / Swarm save. → `TruthPreviewStrip.jsx`
- [x] Library light save shows **unproven** badge; Prove / Publish remains
  **message/toast only** (Marketplace gate deferred to 3.2).
- [x] Selection edge pulse (`bp-edge-animated`); ghost VIEW_ONLY / unsupported
  nodes with **Open in Studio**; inspector typed selects + delete; canvas Delete.
- [x] Selftests green; mobile → web sync via `tools/sync-mobile-views.ps1`.

**Prove latch policy this slice:** Decision 2 toast-only on Prove — Marketplace
gate shipped in Phase **3.2**.

#### Phase 3.2 — Prove latch (Marketplace / live deploy) ✅ (2026-08-05)

**DoD**

- [x] **Prove** runs Truth Report + optional seed robustness; **Marketplace Publish /
  Live Deploy** disabled until latch satisfied. Library / Swarm save stay allowed
  with honest “not proven” badge (already in 3.1).
  → `blueprintProve.js` / `ProveLatchPanel.jsx` / `truth.proof` receipt
- [x] Accept policy matches Studio HonestOptimize: **Robust | Fragile** (Coin-flip /
  Overfit block publish/deploy). Documented in panel + `PROVE_ACCEPT_POLICY_NOTE`.
- [x] Auto-invalidate proof on graph/source edit; explicit Clear proof on edit.

#### Phase 3.3 — Optimize / Autoresearch deep-link ✅ (2026-08-05)

**DoD**

- [x] Deep-link to Studio Autoresearch / Optimize with the same source
  (+ synth tape context via session handoff).
  → `blueprintStudioHandoff.js`; Studio consumes on mount; Evolve / Autoresearch
  stash **Apply to Blueprints** for lift / honest re-lift.

**Deps:** Phase 3.1; charts vendoring · **Effort:** M–L

### Phase 4 — Artifacts, Swarm, Marketplace (L) ✅ (2026-08-05)

**DoD**

- [x] Blueprints save emits Muse artifact refs; Swarm nodes store artifact ids; convert
  warnings preserved for older beam/tree payloads.
  → `blueprintArtifacts.js` / `saveBlueprintArtifactToNode` / convert confirm UI
- [x] Marketplace publish reuses widget publish pattern + **Truth receipt** (Prove latch).
  → `blueprintPublish.js` / `publishBlueprint` in `social.js` (+ web shim dual store)
- [x] Optional `/muse` compile for WASM when dataserver present; else js-tier + honest badge.
  → `blueprintWasm.js` / tier badge on editor (never fake WASM)
- [x] Forge Distill → Logic Lane import/export first-class in save/seed paths.
  → `persistLogicLaneSeedRoundTrip` / `seedForgeFromLogicLaneExport` / provenance forge graph
- [x] Capability matrix documented in `mobile/src/lab/blueprints/README.md` (+ this DoD).

**Deps:** Phase 1–3; social/durable APIs where publishing · **Effort:** L

### Phase 5 — Compose with evolve / Distill / widgets (L)

**DoD**

- MuseGene / `optimize` results return as editable Blueprints (typed).
- Distill pipelines can emit MS (parity vs distillEngine) into Logic Lane /
  Blueprints; Forge page-level Cmp/Bin save remains for Distill-only documents.
- Widget authoring mode: Blueprints shell in Studio / MuseLab, `checkWidget`
  capabilities, Terminal drop.

**Deps:** Phase 2–4; evo palette stability · **Effort:** L

### Phase 6 — Premium interaction polish (M–L)

**DoD**

- Drag-to-connect with type checking; compound collapse; keyboard; multi-select
  on Blueprints hybrid canvas.
- Proposal diff at Muse-AST granularity; optional server LLM (Decision 5 parity).
- Full-bleed MuseLab / Studio Blueprints composition; Forge Distill may keep lighter
  chrome. Vendor sync still one forge tree for Distill.

**Deps:** Phase 1+ · **Effort:** M–L

### Explicit non-goals for early phases

- Replacing `/app/forge` / mobile Forge with the Blueprints IDE.
- Replacing StrategyLab FitArena simulators.
- On-device Haxe compiler.
- Silent “AI autoforge” that publishes without Truth.
- Blocking Library / Swarm save on Truth Report.
- Open-world NP/PD palette in UI before runtime eligibility is green.

---

## 6. Decisions — closed

| # | Topic | Locked (2026-08-04) |
|---|---|---|
| 1 | Canonical editor IR | **Muse Blueprints**; Distill boolean → import / Logic Lane |
| 2 | Prove latch strictness | Truth Report **before Marketplace publish / live deploy only** |
| 3 | Primary home for Muse graph editing | **MuseLab Panel / Studio**; Forge stays Distill-only |
| 4 | Graph rendering | **Hybrid** — library pan/zoom/layout + custom branded node chrome |
| 5 | Graph library | **`@xyflow/react` (xyflow / React Flow)** |

No open product forks remain for those five. Further spikes (document schema field
names, Logic Lane compound UX) stay engineering detail under Phase 0/1.

---

## Appendix A — Evidence anchors (quick)

- Forge v1 purpose + Composer + indicators: `mobile/FORGE_PLAN.md`, `ForgePage.jsx` header.
- Boolean graph IR: `forgeGraph.js`.
- Muse general graph (additive): `tradeLogicGraph.js`; MuseLab wiring: `MuseLabPanel.jsx`.
- Muse projection gaps: `forgeMuseProjection.js`, `museAstToForgeGraph.js`.
- Web host: `mederos-web/src/components/forge/ForgeHost.tsx`, `VENDOR.md`.
- Engine surface: `musescript/runtime/MuseRuntime.hx` (run/panel/optimize/truth/widget/…).
- Evo / panel / NP-PD honesty: `musescript/evo/README.md`.
- Prior Muse cutover thesis: `ai_md/FORGE_STRATEGILAB_MUSESCRIPT_PLAN.md` Phases 3–5.
- Widget publish precedent: `NewMuseWidgetModal.jsx`.

## Appendix B — Tracking

| Doc | Owns |
|---|---|
| **This file** | Forge Distill + MuseLab Blueprints product / architecture overhaul |
| `WEB_SURFACE_PARITY_PLAN.md` | Getting mobile Forge onto web (shipped Phase 6 row #28) |
| `mobile/FORGE_PLAN.md` | Historical Distill Forge v1 ship record + deferred §9 note |
| `FORGE_STRATEGILAB_MUSESCRIPT_PLAN.md` | Lab/service IR cutover companion |
