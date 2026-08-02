# WEB SURFACE PARITY PLAN

> **SHIPPED STATUS (2026-08-01):** Phases **0–7 implemented** in `mederos-web` (engine
> plumbing, vendor seam + Studio panels, charts/forecast/notebook, terminal + workspace,
> library/marketplace/economy, swarm/home/explore, lab/forge/company/games, and device
> analogues: in-tab scheduler, SW notifications, localStorage paper broker, live feeds,
> relay-as-mesh reads). Sync via `tools/sync-web-runtime.ps1` (includes
> `forecast-host-runtime`) and `tools/sync-mobile-views.ps1`.
>
> **Still open:**
> - **Decision 5** — on-device LLM analogue remains **deferred** (manual Autoresearch /
>   assist mode; honest stubs).
>
> **Decision 6 (resolved):** dual Firestore + mederos-relay redundancy for social writes,
> economy wallet, and cross-device paper broker — see `mederos-web/DURABLE_STORE.md`.
> Relay `/durable/{health,mutate,query}` implemented in `kalshi-ai-advisor/relay/`.
> **To go live:** deploy that relay revision, then set web `RELAY_DURABLE_ENABLED=1`
> plus `FIREBASE_PROJECT_ID` + App Hosting/ADC (or `FIREBASE_SERVICE_ACCOUNT_JSON` locally).
>
> Sections below remain the original plan record (matrix, phase DoDs, decisions). Some
> "verified facts" near the top describe the pre-implementation baseline and are kept
> for history — prefer this status block + `mederos-web/src/mobile/VENDOR.md` for
> current ship truth.

Bring everything that *can* run in a browser to **mederos-web**, reusing the existing
mobile/desktop codebase to the maximum extent possible. Originally plan-only; Phases 0–7
are now shipped (see status block above).

**Repos** (paths as on this machine):

| Repo | Path | Stack |
|---|---|---|
| Engine | `kalshai/muse-lab/muse-script` | Haxe → JS bundles (`MuseRuntime`, `MuseDebugSession`, `PineConvert`, `ForecastHostRuntime`) |
| Mobile/desktop app | `kalshai/mobile` | React **19.2.6** + Vite 8 + Capacitor (Android) + Electron; plain-CSS themes |
| Web app | `mederos-web` | Next.js **16.2.11** (App Router) + React **19.2.4** + TypeScript (strict) + Tailwind 4 |

**Core verified facts this plan stands on:**

- **The mobile app already runs on the web.** `mobile/src/platform.js` detects
  `"desktop" | "mobile" | "web"` and the package.json self-describes as "One React + Vite
  codebase, three runtimes." Views are built to degrade honestly when device APIs are absent
  (`IS_WEB`, guarded wrappers). Only **15 files** in `mobile/src` import `@capacitor/*` directly,
  and they are almost all infra modules (`kestrel/*`, `iap/*`, `lib/lanDiscovery.js`,
  `dataserver.js`, `auth.js`, `lab/haptics.js`, `platform.js`) — not views.
- **React versions are compatible** (19.2.6 vs 19.2.4, same major/minor). Both apps use the
  identical CodeMirror stack (`@uiw/react-codemirror` ^4.25.11, `@codemirror/*` 6.x).
- **The glcharts vendoring precedent works and is documented.** `mederos-web/src/glcharts` is a
  straight copy of `mobile/src/glcharts` (plain `.js`/`.jsx`, untouched), documented in
  `src/glcharts/VENDOR.md` ("Copied from kalshai/mobile/src/glcharts... When updating, re-copy
  from the monorepo"). It compiles because `tsconfig.json` has `allowJs: true` and includes
  `**/*.js` / `**/*.jsx`; no `next.config` changes were needed. It is mounted for real:
  `src/components/CandleChart.tsx` dynamically imports `@/glcharts/GlChart.js` inside a
  `"use client"` `useEffect` (client-only, no SSR), used by `/app/charts` and `/platform`.
  One caveat documented in VENDOR.md: `react/SymbolSearchModal.jsx` was excluded because
  `lucide-react` isn't installed on web.
- **The vendored glcharts copy is stale**: mobile's copy has a `forecast/` directory
  (`glcharts/forecast/compute.js` — the ForecastHostRuntime overlay) that the web copy lacks.
- **ForecastHostRuntime has zero presence on web**: no references in `mederos-web/src`, no
  `forecast-host-runtime.js` in `public/` (verified directory listing), and
  `tools/sync-web-runtime.ps1` only builds `build-runtime.hxml` + `build-pine-web.hxml`.
  The bundle is small: `build/js/forecast-host-runtime.js` is **147 KB** (vs 3.3 MB raw
  muse-runtime), built by `build-forecast-host-runtime.hxml`.
- **Engine API surfaces confirmed** in `musescript/runtime/MuseRuntime.hx` (24 public statics),
  `musescript/runtime/MuseDebugSession.hx` (`@:expose`; setBreakpoint, clearBreakpoints,
  stepBar, runToBar, continueRun, inspect, evalWatch, guards, result), and
  `musescript/ew/ForecastHostRuntime.hx` (`kinds()` → `["regime","auction","lattice"]`,
  `forecast(kind, bars, opts)`, never throws across the JS boundary).
- **Engine loading differs by app** and needs a shim, not a rewrite: mobile ESM-imports the
  copied `src/lab/muse-runtime.js` file directly (Vite CJS-interop dance documented in
  `museRuntimeClient.js`); web script-tag-loads hashed files from `/public` via
  `src/lib/museEngine.ts` + generated `src/lib/engineRev.ts`, with long-cache headers in
  `next.config.ts`. Server-side, `src/lib/leaderboardBoard.ts` `eval`s `public/muse-runtime.js`
  in Node for leaderboard rescoring — precedent for server-side engine use.
- **Mobile Python already has three routed backends** (`src/python/pyRouter.js`):
  `jsExactRuntime` (pure-JS port of the distill engine — zero Python needed),
  `pyodideRuntime` (real CPython via Pyodide WASM in a sandboxed Web Worker, loaded from CDN
  `cdn.jsdelivr.net/pyodide/v0.26.4`, module source fetched from the dataserver whitelist),
  `dataserverRuntime` (LAN server). So "Python on the web" is mostly a re-plumbing problem,
  not a new-technology problem.
- **CSS approaches differ but coexist already**: mobile is plain global CSS
  (`theme.css`, `theme.desktop.css`, `theme.lab.css`, `theme.sheets.css`, `theme.strat.css`,
  `theme.swarmecon.css`, `theme.v2.css` + per-feature files like `terminal.css`,
  `instrumentTokens.css`, `chartWorkspace.css`, `flexlayout-theme.css`); web is Tailwind 4 —
  but web already imports a plain CSS file (`src/components/studio/studioInstrument.css`),
  so vendored views can bring their CSS files along.
- **`import.meta.env`** (Vite-only) appears in just 9 mobile files, almost all device/auth
  infra (`iap/*`, `auth.js`, `relay.js`, `kestrel/usageLog.js`, `ServerSettings.jsx`,
  `SignInSheet.jsx`, `CalibrationTrainingModule.jsx`) — a small, enumerable adaptation surface.
- **Web persistence today**: filesystem JSONL under `.data/{analytics,leaderboard,purchases,capture}`
  (ephemeral on Cloud Run/App Hosting — stdout → Cloud Logging is the durable backup) +
  localStorage/sessionStorage client-side + static seed JSON in `src/data/` + the
  **mederos-relay** Cloud Run service (auth magic-links, device pairing, market bars via
  `/api/relay/*` same-origin proxy). Mobile also uses IndexedDB (`kestrel/db.js`) for
  calibration logs / company cache — map those to IDB or localStorage when vendoring.
  ⚠️ No CSP headers today (`next.config.ts` is cache-control only), which leaves room for
  script-tag engines and a future Pyodide worker; any CSP later must allow both.
  Growing social/economy on `.data` inherits the ephemeral-disk limitation (Decision 6).

---

## 1. Summary matrix

Effort: S ≤ 1 day · M = 2–4 days · L = 1–2+ weeks. Class: **A** portable as-is (vendor + trivial shim) ·
**B** portable with adaptation · **C** device-only, web analogue listed · **D** needs backend (has/grow).

| # | Feature | Source files (mobile unless noted) | Target in mederos-web | Reuse mechanism | Class | Phase | Effort |
|---|---|---|---|---|---|---|---|
| 1 | ForecastHostRuntime sync + loader | engine `build-forecast-host-runtime.hxml`, `tools/sync-web-runtime.ps1`; mobile `src/lab/forecastHostClient.js` | `public/forecast-host-runtime.<hash>.js`, `src/lib/engineRev.ts`, `src/lib/museEngine.ts`, new `src/lib/forecastHostClient.ts` | extend sync script; port facade to TS | A | 0 | S |
| 2 | MuseDebugSession typing + wrappers | engine `MuseDebugSession.hx`; mobile `museRuntimeClient.js` (`debugStrategy`) | `src/lib/museEngine.ts` Window decl, `src/lib/museRuntimeClient.ts` | add typings + wrapper | A | 0 | S |
| 3 | optimize/evolve, seedRobustnessSweep, buildReportCard, ledgerEntryFromTruth, runPanel, emitWat/runWasm wrappers | mobile `src/lab/museRuntimeClient.js` | `src/lib/museRuntimeClient.ts` | port wrappers to TS (surface already proven) | A | 0 | S |
| 4 | Vendor seam + shims (platform, haptics, usageLog, dataserver, engine clients) | `src/platform.js`, `src/lab/haptics.js`, `src/kestrel/usageLog.js`, `src/dataserver.js`, `src/lab/museRuntimeClient.js`, `src/lab/forecastHostClient.js` | `src/mobile/**` vendor tree + `src/mobile/_shims/**` | vendor + shim swap at seam files | B | 1 | M |
| 5 | Studio Optimize/Evolve panel | `src/lab/StudioOptimizePanel.jsx` (5.6 KB) + `museRuntimeClient.optimizeStrategy` | Studio side panel on `/studio` | vendor | A | 1 | S |
| 6 | Steppable Debugger | `src/lab/StudioDebugger.jsx` (12 KB) | Studio panel | vendor | A | 1 | S–M |
| 7 | Report Card + seed-robustness sweep | `src/lab/ReportCardPanel.jsx`, `reportCardTypes.js`, `robustness.js` | Studio panel | vendor | A | 1 | S |
| 8 | Honest Ledger | `src/lab/HonestLedgerPanel.jsx`, `honestLedger.js` (localStorage) | Studio panel | vendor | A | 1 | S |
| 9 | Truth Report panel (full) | `src/lab/TruthReportPanel.jsx`, `truthReportTypes.js`, `truthShareCard.jsx` | upgrade `/studio` verdict UI | vendor, reconcile w/ existing `ExplainVerdictPanel.tsx` | A | 1 | M |
| 10 | Indicator Library | `src/lab/IndicatorLibraryPanel.jsx` | Studio panel | vendor (uses forecastHostClient → needs #1) | A | 1 | S |
| 11 | Precommit calibration | `src/lab/precommitCalibration.js`, `PrecommitVerdictPrompt.jsx` | Studio flow | vendor | A | 1 | S |
| 12 | Autoresearch | `src/lab/StudioAutoresearch.jsx`, `studioAutoresearch.js`, `AutoIterationQueue.jsx` | Studio panel | vendor; LLM hooks stubbed to manual mode | B | 1 | M |
| 13 | Repaint receipt panel / Determinism badge | `src/lab/RepaintReceiptPanel.jsx`, `DeterminismBadge.jsx` | merge with web's existing `repaintReceipt.ts` page + Studio | vendor, dedupe | A | 1 | S |
| 14 | wasm assemble path (optional parity) | mobile `museRuntimeClient.js` `loadWabt()` → `emitWat` → `runWasm` | Studio already has `interp\|js\|wasm` tiers via `MuseRuntime.run({tier})` (no `wabt` today) | only add `wabt` if Studio needs the mobile assemble/runWasm path; otherwise skip | B | 1 | S (or skip) |
| 15 | glcharts refresh incl. forecast overlay | `src/glcharts/**` (esp. `forecast/compute.js`, `react/GlChartPanel.jsx`, `indicators/muse/*`) | `src/glcharts` re-copy per VENDOR.md | re-vendor (established precedent) | A | 2 | S–M |
| 16 | Forecast overlays on charts | `src/lab/forecastHostClient.js` (`liveOpts`, `PROJECTED_TAG`), glcharts forecast | `/app/charts` (GlChartPanel instead of bare CandleChart) | vendor + #1 | B | 2 | M |
| 17 | MuseNotebook | `src/lab/MuseNotebook.jsx` (29 KB), `MuseAssistBar.jsx`, `museScriptLang.js` | `/studio` notebook mode or `/app/notebook` | vendor (only CodeMirror + engine deps — both present) | A | 2 | M |
| 18 | Charts workspace (multi-pane) | `src/charting/react/ChartWorkspace.jsx`, `workspaceStore.js`, `sources/*` | `/app/charts` workspace mode | vendor + flexlayout-react dep + bars source → `/api/market/bars` | B | 3 | M–L |
| 19 | Instrument Terminal (dock shell + 12 modules) | `src/terminal/**`: `InstrumentTerminalLayout.jsx`, `shell/*` (FlexLayoutHost), `modules/*` (TruthReport, ReportCard, HonestLeaderboard, HonestLedger, HonestySizing, CalibrationTraining, CockpitPositions, PortfolioXray, RegimeStandDown, LeakAudit, EvolvePanel, WidgetCatalogModal), `widgets/*` | `/app/terminal` (auth'd, desktop-first) | vendor + flexlayout-react; note `InstrumentTerminal.jsx` is just `StrategyStudio shell="terminal"` so #4–13 are prerequisites | B | 3 | L |
| 20 | Widgets registry + palette | `src/widgets/registry.js`, `WidgetPalette.jsx` | terminal/charts Add-widget catalog | vendor | A | 3 | S |
| 21 | Strategy library (rich) | `src/strategies/StrategyLibrary.jsx`, `strategyLib.js`, `CodeCard.jsx`, `MathFormula.jsx` (katex) | `/app/strategies`; supersede Studio's ad-hoc localStorage library | vendor + katex dep | A | 4 | M |
| 22 | Marketplace / social feed | `src/social/StrategyFeed.jsx`, `social.js`, `socialGraph.js`, `follow.js`, `lineage.js`, `profile/*` | `/certified` area or `/app/marketplace` | vendor; point `social.js` `serverBase` at new `/api/social/*` (it already degrades honestly offline) | D-grow | 4 | L |
| 23 | Economy (credits wallet) | `src/economy/ReasoningEconomy.jsx` (24 KB), `credits.js`, `contributions.js`, `inventory.js` | `/app/economy` | vendor; local wallet first, relay wallet later | B / D-grow | 4 | M |
| 24 | Swarm builder + scheduler | `src/swarm/SwarmView.jsx` (41 KB), `SwarmGraph.jsx`, `swarmStore.js`, `swarmScheduler.js`, `scanners.js`, `sizing.js`, `ensembleProtocols.js`, `deployToSwarm.js`, `kestrelForwardSim.js`, `realTape.js` | `/app/swarm` | vendor; scheduler foreground-only on web (background = Phase 7); `swarmSignalBridge`→stub | B | 5 | L |
| 25 | Home dashboard + Forward-backtest theater | `src/home/HomeView.jsx`, `ForwardBacktestHero.jsx`, `ForwardBacktestTheater.jsx`, `forwardSim.js`, `portfolioAggregate.js` | `/app` dashboard | vendor; `portfolioAggregate` reads paper-broker analogue (Phase 7) or demo data | B | 5 | M |
| 26 | Explore feed | `src/components/RankSwipeFeed.jsx`, `RankExploreGrid.jsx`, `RankSlideCard.jsx`, kestrel `rankFromFeatures.js`, `useRankPool.js`, `rankFeedCache.js` | `/app/explore` | vendor; bars via `/api/market/bars`; local rank model runs in browser | B | 5 | M–L |
| 27 | Lab (FitArena, FanChartTheater, OosPerf, DistillBench) | `src/lab/StrategyLab.jsx` (45 KB), `FitArena.jsx`, `FanChartTheater.jsx`, `OosPerf.jsx`, `DistillBench.jsx`, `distill*.js`, `python/pyRouter.js` + backends | `/app/lab` | vendor; `jsExactRuntime` works immediately; Pyodide tier per Decision 3; `dataserverRuntime`→disabled on web | B | 6 | L |
| 28 | Forge | `src/lab/forge/ForgePage.jsx` (43 KB) + pyRouter | `/app/forge` | vendor; same Python decision | B | 6 | L |
| 29 | Company dossier | `src/components/CompanyDossier.jsx` (37 KB), kestrel `secFilings.js`, `companyNav.js`, `companyDossierSync.js` | `/app/company` | vendor; SEC/EDGAR fetch needs a Next API proxy (CORS + rate-limit); LAN dataserver path disabled | B / D-grow | 6 | M–L |
| 30 | Edgar3D | `src/components/EdgarExplorer.jsx` (5 KB) + `src/glgraph` (three.js, troika, d3-force-3d) | `/app/company` 3-D mode | vendor + three.js deps; client-only dynamic import like CandleChart | B | 6 | M |
| 31 | Minigames (duel) | `src/minigames/**` (catalog, duel, grader, vignettes) | `/app/games` or marketing wedge | vendor (self-contained + engine) | A | 6 | M |
| 32 | Background runner (scheduled scans) | `src/kestrel/backgroundRunner.js` (@capacitor/background-runner) | — | **C**: closest analogues = relay-side scheduled jobs (recommended) or Service Worker + Periodic Background Sync (Chromium-only) | C | 7 | M–L |
| 33 | Notifications / signal alerts | `src/kestrel/signalAlerts.js`, `notifications.js` | — | **C**: Web Push via service worker + relay push fan-out; in-tab toasts as fallback | C | 7 | M |
| 34 | Paper broker | `src/kestrel/brokerLocal.js` | — | **C**: localStorage L1 + dual durable sync (`/api/broker/paper`); `durable:true` after sync | C | 7 | M |
| 35 | Live feeds (Kraken/LAN) | `src/kestrel/kraken.js`, `equitiesFeed.js`, `dataserver.js` | — | **C/D-has**: crypto via Kraken public REST/WS from browser (CORS-open); equities/forex already flow via relay+mesh `/api/market/bars` | C | 7 | M |
| 36 | Device mesh sync | `src/sync/deviceMesh.js`, `kestrelSync.js` | — | **C**: relay is the web's mesh; web already pairs to home machines through it (charts page "via mesh") | C | 7 | L |
| 37 | On-device LLM | `src/kestrel/onDeviceLlm.js`, `llmClient.js`, `llmIteration.js` | — | **C**: WebLLM/WebGPU or server LLM via relay; defer (Decision 5) | C | 7 | L |
| 38 | Haptics | `src/lab/haptics.js` | — | **C**: `navigator.vibrate` where available, else no-op (shim already the pattern) | C | 1 (shim) | S |
| 39 | RevenueCat IAP | `src/iap/revenueCat.js` | — | **C/D-has**: web billing already exists (`/billing/*`, `/api/purchases`, `.data/purchases`); mobile even ships `iap/webBilling.js` | C | n/a | — |
| 40 | Electron shell / LAN discovery | `electron/*`, `src/lib/lanDiscovery.js` | — | **C**: inherently not-web; relay replaces LAN discovery | C | n/a | — |

**Inversion note:** mobile lacks PineConvert (web-only today). Out of scope here, but the same
vendor-seam built in Phase 1 makes the reverse port trivial later.

**Classification totals:** **A** portable as-is: **15** (#1–3, 5–11, 13, 15, 17, 20, 21, 31) ·
**B** portable with adaptation: **13** (#4, 12, 14, 16, 18, 19, 23–30) ·
**C** device-only with web analogue: **9** (#32–40) ·
**D** backend: web already **has** what's needed for market bars, auth, leaderboard, purchases,
run-share; must **grow** social endpoints, economy wallet, SEC proxy (3 grow items, folded into
#22, #23, #29).

---

## 2. Reuse mechanism — evidence and architecture

### 2.1 Why vendoring works (the glcharts precedent, generalized)

The question "can mobile JSX views be imported into Next 15/16 + TSX?" is already answered in
production by `src/glcharts`:

- `tsconfig.json`: `"allowJs": true`, `"jsx": "react-jsx"`, include covers `**/*.js`/`**/*.jsx`,
  `checkJs` off → vendored JS compiles without types and without strict-mode noise.
- No `next.config.ts` accommodation was needed (no `transpilePackages`, no webpack override).
- SSR is avoided with the standard pattern: `"use client"` wrapper + dynamic
  `await import("@/glcharts/GlChart.js")` inside `useEffect` (see `CandleChart.tsx`).
  Vendored views that touch `window`/`localStorage` at module scope get the same treatment
  (`next/dynamic` with `ssr: false` or lazy import in a client component).
- React 19.2.x on both sides → no runtime duality; JSX transform identical (`react-jsx`).

### 2.2 The vendor-tree + shim-seam architecture (proposed)

Copy mobile feature directories **wholesale, preserving relative import structure**, under
`mederos-web/src/mobile/` (e.g. `src/mobile/lab/`, `src/mobile/terminal/`, `src/mobile/swarm/`).
Because mobile views import their infra by relative path, replacing a handful of *seam files*
inside the vendor tree re-targets everything above them without editing view code:

| Seam file (path inside vendor tree) | Mobile behavior | Web shim behavior |
|---|---|---|
| `platform.js` | Capacitor/Electron sniffing | constant `PLATFORM="web"`, `prefersDesktopShell()` by viewport |
| `lab/muse-runtime.js` + `lab/museRuntimeClient.js` | ESM-import of copied 3.3 MB engine file | delegate to `src/lib/museEngine.ts` script-tag loader (hashed `/public` file, long-cache); keeps engine out of the Next bundle |
| `lab/forecast-host-runtime.js` + `lab/forecastHostClient.js` | same pattern | delegate to new forecast-host loader (Phase 0) |
| `lab/haptics.js` | @capacitor/haptics | `navigator.vibrate` or no-op |
| `dataserver.js` | LAN dataserver + Capacitor HTTP | route to `/api/relay/*` / Next API routes; return honest `unavailable` shapes otherwise |
| `kestrel/usageLog.js`, `auth.js`, `relay.js` | `import.meta.env`, Capacitor prefs | web analytics (`src/lib/analytics.ts`), web auth (`src/lib/auth.tsx`), relay client (`src/lib/relay.ts`) |
| `kestrel/backgroundRunner.js`, `signalAlerts.js`, `brokerLocal.js`, `onDeviceLlm.js`, `sync/deviceMesh.js`, `iap/revenueCat.js` | device APIs | honest stubs returning `{ ok:false, status:"unavailable", note }` — the mobile UI already renders these gracefully (see `social.js` degradation contract) |

Mobile CSS files come along inside the vendor tree and are imported by the views that use them,
exactly like `studioInstrument.css` already is. Scope collisions with Tailwind are unlikely
(mobile uses prefixed classnames + CSS custom properties), but Phase 1 DoD includes a visual
smoke pass.

`import.meta.env` (Vite-only; breaks under Next/webpack) is confined to 9 files, all of which
are seam files above or device-only modules that get stubbed — no view-level rewrites expected.

### 2.3 What vendoring does *not* solve (and the fallback)

Drift: two copies of Studio/Terminal code. Mitigation short-term: `VENDOR.md`-style manifests
per vendored dir with a re-copy script (like glcharts). Long-term fix is Decision 1
(workspace/shared package). This plan sequences vendoring first because the precedent is proven
and it unblocks every phase without cross-repo build-system surgery.

---

## 3. Engine plumbing first (Phase 0 detail)

All later phases consume this; it is small and zero-risk.

1. **Extend `tools/sync-web-runtime.ps1`:**
   - Also run `haxe build-forecast-host-runtime.hxml` (dev) and expect
     `build/ship/<preset>/forecast-host-runtime.js` for `-Ship` (add the target to the ship
     pipeline / `npm run ship-js` in muse-script if not already produced).
   - Hash + copy `forecast-host-runtime.<hash>.js` and unhashed alias into
     `mederos-web/public/`, mirroring muse-runtime handling.
   - Emit `FORECAST_HOST_REV` / `FORECAST_HOST_URL` into `src/lib/engineRev.ts` and
     `engine-rev.json`.
2. **`next.config.ts`:** add cache-header entries for `/forecast-host-runtime.:hash.js`
   (immutable) and `/forecast-host-runtime.js` (no-store) — copy of existing pairs.
3. **`src/lib/museEngine.ts`:** extend `loadGlobal` to accept `"ForecastHostRuntime"`; add
   Window declaration for it, plus `MuseDebugSession` constructor typing and missing
   `MuseRuntime` members (`optimize`, `evolve`, `seedRobustnessSweep`, `buildReportCard`,
   `ledgerEntryFromTruth`, `debug`, `runPanel`, `runWasm`, `forecastFields`,
   `purgeEmbargoSplit`, `foundationDigest`, `trialsReset/Record/GetCount`) — the full
   24-method surface confirmed in `MuseRuntime.hx`.
4. **`src/lib/museRuntimeClient.ts`:** port the missing wrappers from mobile's
   `museRuntimeClient.js` (optimizeStrategy/evolveStrategy, seedRobustnessSweep,
   buildReportCard, ledgerEntryFromTruth, debugStrategy, runPanelStrategy, emitWat +
   runWasmStrategy, forecastFields, purgeEmbargoSplit, foundationDigest). New
   `src/lib/forecastHostClient.ts` ports `forecast`, `toHostBars`, `liveOpts`,
   `PROJECTED_TAG` from mobile's `forecastHostClient.js`.

**DoD Phase 0:** `pwsh tools/sync-web-runtime.ps1` produces three hashed engines + rev file;
`/engine-rev.json` lists all three; a scratch page can call
`ForecastHostRuntime.kinds()` → `["regime","auction","lattice"]` and step a
`MuseDebugSession` in the browser; leaderboard server-side rescore still passes
(`npm run test:invariants`).

---

## 4. Phases

Dependency edges: `P0 → P1 → {P2, P4} · P2 → P3 · P1 → P5 (P5 uses P2's theater visuals where
available) · P1 → P6 · P7 last (needs relay work; independent of P3–P6 internals)`.

### Phase 0 — Engine plumbing (S–M total)
As §3. Items: #1 (S), #2 (S), #3 (S).

### Phase 1 — Vendor seam + Studio parity panels (M–L total)
High leverage, low risk: everything is pure React + engine calls, and web's `/studio` already
hosts the run/truth loop. Establish `src/mobile/` vendor tree + shims (#4, M), then vendor the
lab panels: Optimize/Evolve #5 (S), Debugger #6 (S–M), ReportCard+sweep #7 (S), Honest Ledger #8
(S), full TruthReportPanel #9 (M — reconcile with existing `ExplainVerdictPanel.tsx` rather than
duplicating), Indicator Library #10 (S), precommit calibration #11 (S), Autoresearch #12 (M,
LLM hooks stubbed), repaint/determinism dedupe #13 (S). Wasm #14: web Studio already
exposes an `interp|js|wasm` tier toggle via `MuseRuntime.run({tier})` — only pull in
`wabt` if we want mobile's explicit assemble path; default is skip.
Note: `/engine` EngineOrgans already runs a *simplified* in-browser evolve demo
(random search + median Sharpe); Phase 1 Evolve means the real
`StudioOptimizePanel` → `MuseRuntime.optimize` surface, not that organ demo.
New deps this phase: `lucide-react` (+ `framer-motion` if the vendored panels animate) —
see Decision 4.

**DoD:** `/studio` exposes Evolve, Debug, Report Card, Ledger, Indicator Library panels running
against real engine calls on synthetic tapes; determinism badge and truth verdicts unchanged for
existing flows; `npm run test:invariants` (honesty/privacy/explain/purchases) passes; no naked
Sharpe anywhere new (mirror mobile's `check-no-naked-sharpe` convention).

### Phase 2 — Charts for real + forecast overlays + Notebook (M total)
Re-vendor glcharts per VENDOR.md including `forecast/` (`register.js` overlays
`FC_EW`/`FC_REGIME`/`FC_AUCTION` → `forecast/compute.js` → ForecastHostRuntime,
`forecast/paint.js`) + `react/GlChartPanel.jsx` + `SymbolSearchModal` (lucide now
present) (#15, S–M). Mount `GlChartPanel` on `/app/charts` with Muse indicator packs
registered and those forecast overlays live, always rendering `PROJECTED_TAG` (#16, M).
Vendor MuseNotebook (#17, M).

**DoD:** `/app/charts` renders indicators + a regime/auction/lattice forecast cloud on live
crypto bars with the PROJECTED tag; notebook cells run against the engine; glcharts selftest
(`glcharts.selftest.mjs`) passes on the refreshed copy.

### Phase 3 — Instrument Terminal + Charts workspace (L total)
Requires Decision 2 (docking). Vendor `terminal/shell` (FlexLayoutHost, TerminalShell,
ToolRail, ChartStage, MobileTerminalChrome), all 12 modules, widgets + registry (#19 L, #20 S),
and `charting/react/ChartWorkspace.jsx` (#18, M–L). Note `InstrumentTerminal.jsx` is a 15-line
wrapper around `StrategyStudio shell="terminal"` — Phase 1's Studio vendor is the real
prerequisite; this phase is mostly shell + modules + layout persistence
(`useTerminalLayout.js` → localStorage, portable as-is).

**DoD:** `/app/terminal` (desktop-first, auth'd) opens with persisted FlexLayout; all 12
modules render live data from a running session; widget catalog adds/removes panels; a port of
`terminal.smoke.selftest.mjs` passes.

### Phase 4 — Library, Marketplace, Economy (L total)
Strategy library #21 (M). Marketplace #22 (L): vendor `StrategyFeed` + social graph; implement
`/api/social/{feed,publish,fork,rate,authors,follow}` against the leaderboard-store pattern —
`social.js` already speaks a clean POST contract with honest offline degradation, so the UI
works from day one even while endpoints land incrementally; integrate with existing
`/certified` + `certifiedSocial.ts` rather than forking a second social surface. Economy #23
(M): local wallet first; relay-backed wallet when Decision on storage backend (see §5 risk)
resolves.

**DoD:** publish → browse → fork → rate round-trips against web backend with lineage recorded;
certified profiles show fork lineage; economy wallet persists and gates paid actions locally.

### Phase 5 — Swarm, Home dashboard, Explore (L total)
Swarm #24 (L): vendor SwarmView/SwarmGraph/store/scheduler; scheduler runs foreground-only
(tab open) with honest labeling — background execution arrives in Phase 7; `swarmSignalBridge`
stubbed to unavailable. Home #25 (M): ForwardBacktestHero/Theater + portfolio dashboard on
demo/paper data. Explore #26 (M–L): rank feed on `/api/market/bars` data, rank model scored
in-browser.

**DoD:** deploy-to-swarm from Studio creates a swarm that forward-sims in a live tab; Home shows
portfolio + theater; Explore swipe/grid feed ranks real symbols; all device-only bridges show
honest "unavailable on web" states, not broken UI.

### Phase 6 — Python Lab/Forge, Company/Edgar3D, minigames (L total)
Lab #27 + Forge #28 (L, gated on Decision 3): `jsExactRuntime` ships immediately (pure JS);
Pyodide tier adds real-CPython parity (`parityCheck` gem) with module sources served from
`public/pysrc/` or a Next route instead of the dataserver whitelist. `dataserverRuntime`
disabled on web. Company #29 (M–L): new `/api/edgar/*` proxy (CORS + SEC rate-limit + UA
header); Edgar3D #30 (M): add `three`/`troika-three-text`/`d3-force-3d`, client-only dynamic
import. Minigames #31 (M).

**DoD:** DistillBench runs js-exact in browser; if Pyodide adopted, parity check
(js-exact vs CPython) passes in-browser; dossier + 3-D filings explorer load via proxy;
duel minigame playable.

### Phase 7 — Device-only analogues (M–L total)
Web Push notifications #33 (M): service worker + relay fan-out for signal alerts. Background
work #32 (M–L): prefer relay-side scheduled jobs (portable, reliable) over Periodic Background
Sync (Chromium-only). Paper broker #34 (M): localStorage single-device now, relay-hosted for
durability. Live feeds #35 (M): Kraken public WS/REST directly from browser for crypto;
equities stay on relay/mesh. Mesh #36: relay *is* the web mesh (already partially true —
`/app/charts` shows "via mesh"). On-device LLM #37: defer per Decision 5. Haptics #38 already
shimmed in Phase 1. IAP #39 and Electron/LAN #40: n/a (web billing exists).

**DoD:** user can opt into push alerts and receive one from a relay-side scheduled scan with the
tab closed; paper trades persist; crypto charts stream live; every remaining device-only feature
has an explicit, honest "requires the app" affordance linking to `/downloads`.

---

## 5. Decisions requiring user input

### Decision 1 — Code-sharing mechanism (mobile views → web)

| | **Vendoring (glcharts pattern)** | **npm workspaces / shared package** | **git subtree/submodule of `mobile/src`** |
|---|---|---|---|
| Pros | Proven in this exact codebase (`src/glcharts` + VENDOR.md); zero build-system change; web can shim seam files freely; repos deploy independently | Single source of truth, no drift; changes flow both ways; typed package boundary possible | History-preserving sync; no npm plumbing; whole-tree updates in one command |
| Cons | Drift risk; re-copy discipline needed; two places to fix bugs | Repos live in different roots (`kalshai/` vs `Development/`) — needs a meta-workspace or path deps; Next+Vite both consuming raw JSX package needs `transpilePackages` + careful config; couples release cadence | Submodules are operationally painful on Windows/CI; still one physical copy per repo; shims require an overlay dir anyway |
| Effort to start | S | M–L | M |
| Recommendation | **Yes for Phases 1–6** (with per-dir VENDOR.md + a `tools/sync-mobile-views.ps1` re-copy script) | Revisit after Phase 3 if drift hurts | No |

### Decision 2 — Docking layout for Terminal / Charts workspace

| | **flexlayout-react ^0.10** (what mobile uses) | **dockview** | **react-mosaic** |
|---|---|---|---|
| Pros | Terminal shell, saved layouts (`useTerminalLayout.js`), theme CSS (`flexlayout-theme.css`) and smoke tests reuse **unchanged**; zero porting cost | Actively maintained, polished UX, first-class TS | Simple, tiny |
| Cons | Slow-moving upstream; docs thin | Every layout call-site, persistence schema, and theme must be rewritten; saved-layout migration | No tabsets/stacking like the terminal needs; major rewrite |
| New dep on web? | Yes (~small) | Yes | Yes |
| Recommendation | **Yes** — reuse-maximizing by definition | Only if flexlayout becomes a blocker | No |

### Decision 3 — Python for Lab/Forge on web

| | **Pyodide (CDN, sandboxed worker)** | **Server-side Python (relay/Cloud Run job)** | **js-exact only (defer Python)** |
|---|---|---|---|
| Pros | `pyodideRuntime.js` backend **already written and routed** (`pyRouter` prefers lightest tier); sandboxed for untrusted code; offline after first ~10 MB CDN load; keeps the "runs in front of you" honesty story; parity gem (js vs CPython) works in-browser | No client download; full numpy/scipy; strongest for heavy jobs | Zero new surface; DistillBench works today via the pure-JS port |
| Cons | ~10 MB first load; needs `/lab/pysrc/*` module-source endpoint replacement (serve from `public/pysrc` or API route); COOP/COEP headers if SharedArrayBuffer ever needed | New backend service + queue + cost; loses on-device story; latency | Loses CPython parity showpiece and any numpy-dependent Forge features |
| New dep? | Runtime CDN script (pin version, optionally self-host in `public/pyodide/`) | Infra, not npm | None |
| Recommendation | **js-exact immediately (Phase 6 start) + Pyodide tier behind it** — mirrors mobile's own routing philosophy; server tier only if a concrete heavy workload demands it | Later, on demand | As the floor, not the ceiling |

### Decision 4 — Inherited npm deps from mobile (needed by vendored views)

Not really 2–3 alternatives per package — the alternative to each is rewriting working views.
Proposed policy, per package, adopt-when-phase-needs-it:

| Package | First needed | Size/risk | Alternative (cost) |
|---|---|---|---|
| `lucide-react` | Phase 1 (panels), unblocks glcharts `SymbolSearchModal` | tiny, tree-shaken | swap every icon usage (~dozens of files) for inline SVG — not worth it |
| `wabt` | Phase 1 only if #14 assemble path wanted | lazy-loaded on mobile; web Studio already has engine-internal wasm tier without it | skip (recommended) — keep web's `MuseRuntime.run({tier:"wasm"})` path |
| `framer-motion` | Phase 1–2 (panel/theater motion) | moderate | strip animations from vendored views (invasive edits) |
| `flexlayout-react` | Phase 3 | small | Decision 2 |
| `katex` | Phase 4 (`MathFormula.jsx`) | moderate, lazy | render formulas as plain text |
| `three` + `troika-three-text` + `d3-force-3d` | Phase 6 (Edgar3D) | large, client-only dynamic import | skip Edgar3D (dossier still ships) |
| `klinecharts`, `@stdlib/*` | only if a vendored view actually imports them (verify at copy time) | — | exclude those views' optional paths |

**Recommendation:** adopt on first use, always behind lazy `import()` so marketing pages pay nothing.

### Decision 5 — On-device LLM analogue (Autoresearch/assist, Phase 7)

| | **WebLLM (WebGPU)** | **Relay-hosted LLM endpoint** | **Omit on web (manual mode)** |
|---|---|---|---|
| Pros | Truest analogue to on-device; private | Works on all browsers; small client | Zero cost; Autoresearch already has a no-LLM manual path |
| Cons | Multi-GB model download; WebGPU support gaps | Server cost; privacy story changes | Feature gap vs app |
| Recommendation | Defer; ship manual mode in Phase 1 and revisit after P7 basics | Candidate if demand appears | **Default for now** |

**Status:** still deferred. Phase 7 shipped without an LLM analogue; shims stay honest
`ineligible`/`unavailable`, Autoresearch/Forge assist remain manual.

### Decision 6 — Dual relay + Firestore redundancy (resolved)

**Choice:** BOTH. Durable mutations for social (publish/fork/rate), economy wallet, and
cross-device paper broker **dual-write** to Firestore and mederos-relay.

| Role | Backend | Policy |
|------|---------|--------|
| Read primary | **Firestore** | Structured docs; Admin SDK on App Hosting |
| Write replica / auth home | **mederos-relay** | JWT identity already lives here; `/durable/*` replica when `RELAY_DURABLE_ENABLED=1` |
| Conflict | Last-writer-wins by `updatedAt` + stable `mutationId` | Fail only if both backends reject; degraded-ok if one accepts |
| Forbidden | Ephemeral `.data/` for social/economy/broker | Leaderboard JSONL remains separate until absorbed |

Web implementation: `mederos-web/src/lib/durableStore/` + `DURABLE_STORE.md`. Product
surfaces: `/api/social/*`, `/api/wallet`, `/api/economy/event`, `/api/broker/paper`.

**Status:** decided + web dual layer shipped + relay `/durable/*` implemented
(`kalshi-ai-advisor/relay/{routes_durable,durable_store}.py`, Firestore-backed,
JWT auth, mutationId idempotency). **Deploy gate:** ship relay revision, then set
`RELAY_DURABLE_ENABLED=1` on web with `FIREBASE_PROJECT_ID` + credentials (see
`mederos-web/DURABLE_STORE.md`). Until then web degrades to Firestore-only /
memory-fallback.

---

## 6. Risks & mitigations

- **Vendor drift** — per-dir VENDOR.md + one re-copy script + (optionally) a CI hash check
  comparing vendored seams against mobile. Revisit Decision 1 after Phase 3.
- **Bundle bloat** — every vendored feature loads via `next/dynamic`/lazy `import()`; engine
  bundles stay as `/public` script tags (never enter the webpack graph), matching today's
  architecture. The mobile app solves the identical problem the same way (`FULL_VIEWS` lazy
  registry, "cold start never pays for muse-runtime/wabt/three.js").
- **CSS collisions** — mobile themes are custom-property driven and class-prefixed; import
  per-feature CSS only inside the lazy view; visual smoke pass per phase DoD.
- **SSR breakage** — vendored views are client components by policy; module-scope
  `window`/`localStorage` access is confined behind dynamic import (CandleChart pattern).
- **Honesty regressions** — both repos enforce "no naked Sharpe" checks
  (`check-no-naked-sharpe.mjs` mobile, `check-studio-honesty.mjs` web); vendored panels come
  from the stricter surface, and each phase's DoD includes `npm run test:invariants`.

---

## 7. Feature-count summary

- **Portable as-is (A):** 15
- **Portable with adaptation (B):** 13
- **Device-only, web analogue planned (C):** 9
- **Backend items:** web already has 5 (auth, market bars, leaderboard, purchases/billing,
  run-share); must grow 3 (social endpoints, economy wallet, SEC/EDGAR proxy)
- **Phases:** 0 engine plumbing → 1 vendor seam + Studio panels → 2 charts/forecast/notebook →
  3 terminal + workspace → 4 library/marketplace/economy → 5 swarm/home/explore →
  6 Python lab/forge + company/3-D + games → 7 device-analogues (push, background, broker,
  feeds, mesh).
