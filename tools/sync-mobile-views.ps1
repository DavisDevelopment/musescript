# sync-mobile-views.ps1 — re-copy vendored mobile view files into mederos-web/src/mobile.
#
# Companion to sync-web-runtime.ps1 (same cross-repo layout assumptions). The web app
# vendors mobile feature files wholesale, preserving relative import structure, under
# mederos-web/src/mobile/ (WEB_SURFACE_PARITY_PLAN.md §2.2). A handful of SEAM files
# inside that tree are WEB SHIMS (src/mobile/_shims/* + thin re-export files) and must
# NEVER be overwritten by a re-copy — they re-target engine loading, platform sniffing,
# telemetry, and the LAN dataserver to web equivalents.
#
#   pwsh tools/sync-mobile-views.ps1            # re-copy everything in the manifest
#   pwsh tools/sync-mobile-views.ps1 -DryRun    # show what would be copied
#
# When vendoring NEW mobile files: add them to $files below (keep the phase comments),
# re-run, and check `npx tsc --noEmit` + `npm run build` in mederos-web.

param([switch]$DryRun)

$ErrorActionPreference = "Stop"

$mobileSrc = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\mobile\src")
$webRoot = Resolve-Path (Join-Path $PSScriptRoot "..\..\..\..\mederos-web")
$vendorRoot = Join-Path $webRoot "src\mobile"

# ── Seam files (relative to src/mobile) — web shims, never overwritten ──────
$seamFiles = @(
  "platform.js",
  "dataserver.js",
  "relay.js",                       # Cloud Run relay client (import.meta.env) — web maps /market/bars → /api/market/bars
  "lab\haptics.js",
  "lab\museRuntimeClient.js",
  "lab\forecastHostClient.js",
  "lab\muse-runtime.js",            # engine loads from /public via script tag on web
  "lab\forecast-host-runtime.js",   # same
  "kestrel\usageLog.js",
  "kestrel\autoIteration.js",       # native retrain pipeline — honest empty stub on web
  "kestrel\signalAlerts.js",        # desktop/Capacitor notifications — web Notification API or honest queued_ui_only
  "kestrel\equitiesFeed.js",        # CapacitorHttp Yahoo fetch — web goes via /api/market/bars; synthetic stays deterministic
  # Phase 4 seams (Library / Marketplace / Economy):
  "auth.js",                        # Capacitor auth + import.meta.env — web reads the mederos.session localStorage token
  "social\social.js",               # Decision 6: auth-aware durable publish/fork/rate (web _shims/social.ts)
  "kestrel\llmClient.js",           # dataserver Ollama proxy — web returns the canned note verbatim (source: "note")
  "lab\onDeviceExplain.js",         # on-device LLM (deferred, Decision 5) — honest unavailable stub
  "components\SignInSheet.jsx",     # Capacitor/Google/Apple sign-in sheet — web auth card (magic-link session via /login)
  "iap\IapPaywall.jsx",             # RevenueCat credit packs — web billing; server wallet via Decision 6 dual store
  # Phase 5 seams (Swarm / Home / Explore):
  "kestrel\notifications.js",       # Capacitor LocalNotifications — web Notification API foreground best-effort, honest false
  "kestrel\onDeviceLlm.js",         # native OnDeviceLlm plugin (LiteRT) — honest ineligible/unavailable stub on web
  # Phase 7 seams (device analogues — plan item 34, web paper broker):
  "kestrel\brokerLocal.js",         # local mederos_node BYO client — web serves the same surface from the localStorage PAPER BROKER
  "kestrel\krakenTrade.js"          # local-node trade client — web preview/approve/execute against the paper broker (dry_run, simulated fills)
)

# ── Vendored directory trees (relative to mobile/src) ───────────────────────
# Whole directories copied recursively (minus excludes). Phase 2 consolidated
# the app's ONE glcharts copy here (src/mobile/glcharts) — the old standalone
# src/glcharts vendor was deleted so chartBridge / indicatorRegistry are a
# single module instance shared by IndicatorLibraryPanel and GlChartPanel.
$trees = @(
  @{ root = "glcharts"; exclude = @("demo") },  # Phase 2 — full chart engine incl. forecast/ + geom/ + react/
  # Phase 3 — Instrument Terminal (item 19): shell (FlexLayoutHost/TerminalShell/docks),
  # chrome, all modules, widgets, fixtures + CSS. Excluded:
  #   InstrumentTerminal.jsx / index.js — the 15-line wrapper imports mobile's
  #     StrategyStudio.jsx (not vendored); the web run-context host is
  #     mederos-web/src/components/terminal/TerminalHost.tsx instead.
  #   __tests__ — node smoke selftest is ported at mederos-web/scripts/check-terminal-smoke.mjs
  #     (same assertions, web paths).
  @{ root = "terminal"; exclude = @("__tests__", "InstrumentTerminal.jsx", "index.js", "README.md") },
  # Phase 3 — Charts workspace (item 18): ChartWorkspace + workspaceStore + sources/*
  # + classic klinecharts ChartPanel stack + settings persistence (kestrel/db → IndexedDB).
  @{ root = "charting"; exclude = @() },
  # Phase 3 — unified widget registry + palette (item 20).
  @{ root = "widgets"; exclude = @() },
  # Phase 4 — Strategy library (item 21): StrategyLibrary + strategyLib seed list +
  # CodeCard + MathFormula (katex is lazy-imported inside; web adopted the dep).
  @{ root = "strategies"; exclude = @("POLISH_NOTES_strat.md") },
  # Phase 4 — Marketplace / social feed (item 22): StrategyFeed + the certified
  # reputation graph (socialGraph/lineage/certifiedCredential/follow) + CertifiedProfile.
  # Node selftests stay in the mobile repo (not part of the web build).
  @{ root = "social"; exclude = @("certifiedCredential.selftest.js", "follow.selftest.js",
                                  "lineage.selftest.js", "socialGraph.selftest.js") },
  # Phase 4 — Reasoning economy (item 23): local wallet (credits/contributions via
  # kestrel/db IndexedDB — dataserver seam is null on web so the wallet stays
  # device-local until Decision 6 lands), perspective pricing, ReasoningEconomy +
  # InventoryView.
  @{ root = "economy"; exclude = @("POLISH_NOTES_swarmecon.md") },
  # Phase 5 — Swarm builder + scheduler (item 24): SwarmView/SwarmGraph/store/exec +
  # foreground scheduler + mycelium canvas. swarmSignalBridge is PURE (no I/O) and
  # vendors as-is; order relay + device mesh degrade honestly (no hub on web).
  @{ root = "swarm"; exclude = @("POLISH_NOTES_swarm.md", "run-selftests.mjs", "*.selftest.*") },
  # Phase 5 — Home dashboard (item 25): HomeView + ForwardBacktestHero/Theater +
  # portfolioAggregate (paper/demo data until Phase 7's paper broker).
  @{ root = "home"; exclude = @("POLISH_NOTES_home.md") },
  # Phase 6 — glgraph 3D constellation engine (item 30, also used by the Lab's
  # Kestrel theaters): three.js scene + d3-force-3d layout worker + troika
  # labels. Client-only WebGL — mount via next/dynamic ssr:false. demo/ is the
  # vite playground, not part of the app surface.
  @{ root = "glgraph"; exclude = @("demo") },
  # Phase 6 — full minigames surface (item 31): vignette catalog/generator/
  # grader + feed MiniGameCard + link-based calibration Duels (local-first —
  # commit/verify/score all run client-side; no server component).
  @{ root = "minigames"; exclude = @("minigames.selftest.js") },
  # Phase 6 — Forge visual strategy editor (item 28): ForgePage + ForgeCanvas +
  # graph/tree projections + indicatorStore. forgeLlm routes through the
  # onDeviceLlm/llmClient seams (honest manual mode on web).
  @{ root = "lab\forge"; exclude = @("*.selftest.*") }
)

# ── Vendored file manifest (relative to mobile/src) ─────────────────────────
$files = @(
  # Phase 1 — Studio parity panels (WEB_SURFACE_PARITY_PLAN.md §4 Phase 1, items 5-13)
  "lab\StudioOptimizePanel.jsx",
  "lab\StudioDebugger.jsx",
  "lab\ReportCardPanel.jsx",
  "lab\reportCardTypes.js",
  "lab\robustness.js",
  "lab\distillStats.js",
  "lab\HonestLedgerPanel.jsx",
  "lab\honestLedger.js",
  "lab\TruthReportPanel.jsx",
  "lab\truthReportTypes.js",
  "lab\truthShareCard.jsx",
  "lab\explainVerdict.js",
  "lab\IndicatorLibraryPanel.jsx",
  "lab\museScriptLang.js",
  "lab\precommitCalibration.js",
  "lab\PrecommitVerdictPrompt.jsx",
  "lab\StudioAutoresearch.jsx",
  "lab\studioAutoresearch.js",
  "lab\AutoIterationQueue.jsx",
  "lab\museLabClient.js",
  "lab\studioTrialsSession.js",
  "lab\studioPboCloud.js",
  "lab\RepaintReceiptPanel.jsx",
  "lab\DeterminismBadge.jsx",
  "lab\repaintReceipt.js",
  "lab\repaintShareCard.jsx",
  # Phase 2 — MuseNotebook (item 17) + GlChartPanel's one out-of-tree import.
  # (glcharts itself is now a whole-tree copy — see $trees above; useChartChrome.js
  # rides along in the Phase 3 charting tree now.)
  "lab\MuseNotebook.jsx",
  "lab\MuseAssistBar.jsx",
  "lab\notebookDeploy.js",          # pure cell→strategy-source extraction (notebook deploy flow)
  "lab\DeployToSwarmSheet.jsx",     # deploy-to-swarm sheet — engine via museRuntimeClient seam
  # Phase 3 — Instrument Terminal + Charts workspace out-of-tree infra (items 18-20).
  # Everything here is device-API-free and portable as-is; device touchpoints
  # (relay.js, kestrel/signalAlerts.js, kestrel/equitiesFeed.js) are seam shims.
  "kestrel\db.js",                  # IndexedDB meta store — workspace/chart-settings persistence
  "kestrel\kraken.js",              # keyless Kraken public REST (CORS-open in browsers)
  # kestrel\brokerLocal.js became a Phase 7 SEAM (web paper broker) — see $seamFiles
  "lib\withTimeout.js",
  "lib\demoData.js",                # global "Demo data" switch (localStorage)
  "lib\useDemoData.js",
  "hooks\useMediaQuery.js",
  "lab\honestLeaderboard.js",       # local Honest Leaderboard store (HonestLeaderboardModule)
  "lab\runShare.js",                # share-token codec used by honestLeaderboard
  "lab\forge\forgeIndicators.js",   # form-indicator eval (charting userIndicator.js)
  "python\distillEngine.js",        # pure-JS distill port (forgeIndicators dependency)
  # Phase 4 — Library / Marketplace / Economy out-of-tree helpers (items 21-23).
  # All device-API-free; the device-flavored imports these views make
  # (auth.js, kestrel/llmClient.js, lab/onDeviceExplain.js, components/SignInSheet.jsx,
  # iap/IapPaywall.jsx) are seam shims — see $seamFiles.
  "lab\MuseCode.jsx",               # shared MuseScript tokenizer spans (CodeCard highlighting)
  "lab\motionGovernor.js",          # pure motion-tier governor (useCountUp dependency)
  "lib\motionGovernorSingleton.js",
  "lib\localStore.js",              # plain localStorage JSON helpers (follow.js dependency)
  "hooks\useCountUp.js",            # animated count-up (ReasoningEconomy balance)
  "kestrel\usageEvents.js",         # pure event-name catalog
  "kestrel\forecasterRating.js",    # streak/rating from IndexedDB calibration entries
  "components\Skeleton.jsx",        # loading skeletons (library/feed)
  # Phase 5 — Explore feed (item 26) + Swarm/Home out-of-tree helpers (items 24-25).
  # Everything below is device-API-free; the device touchpoints these views reach
  # (equitiesFeed, dataserver, usageLog, haptics, llmClient, notifications,
  # onDeviceLlm) are seam shims. @capacitor/haptics direct imports (SymbolPicker,
  # NumberField) resolve via the next.config.ts resolveAlias to _shims/capacitorHaptics.
  "feedSource.js",                  # FeedSource contract + live_model/custom_universe/simgraph sources
  "drawerMotion.js",                # shared drawer motion preset (framer-motion)
  "components\RankSwipeFeed.jsx",
  "components\RankExploreGrid.jsx",
  "components\RankSlideCard.jsx",
  "components\SwipeCarousel.jsx",
  "components\IntuitionSlide.jsx",
  "components\RecoHud.jsx",
  "components\ContribChart.jsx",
  "components\OfflineEmpty.jsx",
  "components\TradeSheet.jsx",      # trade proposal sheet — krakenTrade preview/execute degrade honestly (no local node)
  "components\NumberField.jsx",
  "components\DeployBookSheet.jsx", # human-approval order book sheet (swarm oversight)
  "desktop\useResizablePanel.js",
  "desktop\ResizeHandle.jsx",
  "kestrel\explain.js",             # pure rank-explanation math (combinerBars/cloudFanSketch/rationale)
  "kestrel\exploreIntro.js",
  "kestrel\feedUtils.js",
  "kestrel\localReco.js",           # on-device reco state (localStorage)
  "kestrel\rankFeedCache.js",
  "kestrel\rankFromFeatures.js",
  "kestrel\useRankPool.js",
  "kestrel\krakenLinks.js",         # external kraken.com deep links (pure)
  # kestrel\krakenTrade.js became a Phase 7 SEAM (paper preview/approve/execute) — see $seamFiles
  "kestrel\liveGate.js",
  "kestrel\riskEnvelope.js",
  "kestrel\tradingBridge.js",       # pure book/order-plan math
  "kestrel\kestrelEngine.js",       # live_model rank pipeline (runKestrelLive)
  "kestrel\modelRegistry.js",       # fetches /models/* static assets (synced below)
  "kestrel\kestrelConfig.js",
  "kestrel\scoreBars.js",
  "kestrel\encoder.js",             # pure-JS encoder (no ONNX)
  "kestrel\channels.js",
  "kestrel\forecastHead.js",
  "kestrel\portfolio.js",
  "kestrel\paperTrack.js",
  "kestrel\paperGate.js",
  "kestrel\robinhood.js",           # quotes-only client on top of equitiesFeed seam
  "kestrel\companyNav.js",          # pub/sub open-company channel (silent no-op with no subscriber)
  "lab\SymbolPicker.jsx",
  "lab\uiMuseEvents.js",          # Lab/terminal UI MuseEvents host pumps (ui.click|selection|focus|command)
  "lab\watchlistMuseEvents.js",   # watchlist.add|remove|ping pumps (SymbolPicker)
  "lab\orderMuseEvents.js",       # broker/order status pumps (TradeSheet / DeployBookSheet)
  "lab\canvas\graphArena.js",
  "lab\distillExplain.js",
  "lab\distillFolds.js",
  "lab\distillSearch.js",
  "lab\forge\forgeGraph.js",
  "lab\forge\forgeLlm.js",          # LLM composer — routes through onDeviceLlm/llmClient seams (honest manual mode)
  "lib\accountDialog.js",           # pub/sub account-dialog channel (web host subscribes)
  "lib\offlineError.js",
  "minigames\MiniGameCard.jsx",     # feed inline minigame card (Phase 6 added the full tree — see $trees)
  "minigames\minigames.css",        # imported by MiniGameCard (mg-* prefixed, collision-safe)
  "minigames\annotations.js",
  "minigames\catalog.js",
  "minigames\generator.js",
  "minigames\grader.js",
  "minigames\vignettes.js",
  "python\backtest.js",
  "python\derive.js",
  "python\distillPipeline.js",
  "python\distillTree.js",
  "python\murmuration.cjs",
  "python\murmurationBridge.js",
  "python\pyRouter.js",             # routes to lightest tier; jsExact works everywhere, dataserver tier null on web
  "python\backends\jsExactRuntime.js",
  "python\backends\pyodideRuntime.js",
  "python\backends\dataserverRuntime.js",
  "sync\deviceMesh.js",             # mesh hub via dataserver seam — honest no-op with no hub on web
  "sync\kestrelSync.js",
  "sync\swarmOrderRelay.js",        # local-first order feed ring buffer + best-effort mesh push
  # Phase 6 — Lab (item 27): StrategyLab + FitArena/FanChart/KestrelRun theaters,
  # DistillBench + OosPerf, saved rules, on-device run loop. Python routing is
  # Decision 3 (LOCKED): pyRouter prefers jsExact → Pyodide (static /pysrc
  # mirror) → dataserver tier honestly absent via the seam.
  "lab\StrategyLab.jsx",
  "lab\FitArena.jsx",
  "lab\FanChartTheater.jsx",
  "lab\OosPerf.jsx",
  "lab\DistillBench.jsx",
  "lab\LabCharts.jsx",
  "lab\TheaterHud.jsx",
  "lab\theaterUtils.js",
  "lab\tunableMetrics.js",
  "lab\useChartWidth.js",
  "lab\EditableMetric.jsx",
  "lab\AgentSparkline.jsx",
  "lab\KestrelRunTheater.jsx",      # 3D run theater (glgraph)
  "lab\kestrelRunGraph.js",
  "lab\KestrelDistillGlobe.jsx",    # 3D distill globe (glgraph)
  "lab\kestrelVizGraph.js",
  "lab\SavedRules.jsx",
  "lab\MuseLabPanel.jsx",
  "lab\MurmurationModal.jsx",
  "lab\labStore.js",
  "lab\labClient.js",               # dataserver-backed presets/server runs — degrade honestly (no LAN server on web)
  "lab\onDeviceRun.js",             # on-device run loop via pyRouter (jsExact/Pyodide tiers on web)
  "lab\distillRunner.js",
  "lab\oosSplit.js",
  "lab\synthBars.js",
  "lab\canvas\fanCanvas.js",
  "lab\canvas\tendrilField.js",
  "sync\computeRouter.js",          # distill compute routing — local tiers on web (mesh hub honestly absent)
  # Phase 6 — Company dossier + Edgar3D (items 29-30). Both views read the
  # dataserver seam; the web shim scopes a same-origin /api/edgar base while
  # the company page is mounted (SEC proxy) — LAN dataserver stays disabled.
  "components\CompanyDossier.jsx",
  "components\EdgarExplorer.jsx",
  "kestrel\companyDossierSync.js"   # hold-and-sync bar queue — flush degrades honestly (no /equities/bars/sync on web)
)

# Expand $trees into concrete file entries so the copy loop + VENDOR.md
# generation treat them exactly like hand-listed files.
foreach ($tree in $trees) {
  $srcRoot = Join-Path $mobileSrc $tree.root
  if (-not (Test-Path $srcRoot)) { Write-Error "missing tree in mobile repo: $srcRoot" }
  $items = Get-ChildItem -Path $srcRoot -Recurse -File
  foreach ($item in $items) {
    $rel = $item.FullName.Substring((Resolve-Path $mobileSrc).Path.Length + 1)
    $parts = $rel -split "\\"
    $excluded = $false
    foreach ($ex in $tree.exclude) {
      # exact path-part match, or wildcard filename match (e.g. "*.selftest.*")
      if ($parts -contains $ex -or $item.Name -like $ex) { $excluded = $true; break }
    }
    if (-not $excluded -and $files -notcontains $rel) { $files += $rel }
  }
}

$copied = 0
$skipped = 0
foreach ($rel in $files) {
  if ($seamFiles -contains $rel) {
    Write-Warning "manifest entry '$rel' is a seam file — skipping (remove it from `$files)"
    $skipped++
    continue
  }
  $src = Join-Path $mobileSrc $rel
  if (-not (Test-Path $src)) {
    Write-Error "missing in mobile repo: $src"
  }
  $dst = Join-Path $vendorRoot $rel
  $dstDir = Split-Path $dst -Parent
  if ($DryRun) {
    Write-Host "would copy $rel"
  } else {
    if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
    Copy-Item $src $dst -Force
  }
  $copied++
}

# ── Static model assets (Phase 5 Explore) ───────────────────────────────────
# kestrel/modelRegistry.js fetches ./models/registry.json + per-model manifest/
# encoder JSON. Mobile serves them from public/models; the web app mirrors them
# at public/models (next.config.ts rewrites /app/models/* → /models/* because
# the vendored fetch URL is page-relative). ~5 MB total, all static JSON.
$mobilePublicModels = Join-Path (Split-Path $mobileSrc -Parent) "public\models"
$webPublicModels = Join-Path $webRoot "public\models"
if (Test-Path $mobilePublicModels) {
  $modelItems = Get-ChildItem -Path $mobilePublicModels -Recurse -File
  foreach ($item in $modelItems) {
    $rel = $item.FullName.Substring((Resolve-Path $mobilePublicModels).Path.Length + 1)
    if ($DryRun) {
      Write-Host "would copy models\$rel"
    } else {
      $dst = Join-Path $webPublicModels $rel
      $dstDir = Split-Path $dst -Parent
      if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
      Copy-Item $item.FullName $dst -Force
    }
    $copied++
  }
}

# ── Static python engine sources (Phase 5 Swarm forward-sim) ─────────────────
# python/backends/pyodideRuntime.js fetches ./pysrc/{name}.py page-relative
# (mobile bundles them at public/pysrc). Mirroring them lets the Pyodide tier
# run mobile_sim/mobile_distill in-browser on web instead of failing over to
# the (absent) LAN dataserver. next.config.ts rewrites /app/pysrc/* → /pysrc/*.
$mobilePublicPysrc = Join-Path (Split-Path $mobileSrc -Parent) "public\pysrc"
$webPublicPysrc = Join-Path $webRoot "public\pysrc"
if (Test-Path $mobilePublicPysrc) {
  $pysrcItems = Get-ChildItem -Path $mobilePublicPysrc -Recurse -File
  foreach ($item in $pysrcItems) {
    $rel = $item.FullName.Substring((Resolve-Path $mobilePublicPysrc).Path.Length + 1)
    if ($DryRun) {
      Write-Host "would copy pysrc\$rel"
    } else {
      $dst = Join-Path $webPublicPysrc $rel
      $dstDir = Split-Path $dst -Parent
      if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Path $dstDir -Force | Out-Null }
      Copy-Item $item.FullName $dst -Force
    }
    $copied++
  }
}

# ── Static root data assets (Phase 6 Lab offline agents + Phase 5 real tape) ─
# StrategyLab fetches ./sample_agents.json (offline sampled-agent bundle) and
# swarm/realTape.js fetches ./real_agent_frames.json (real daily bars tape) —
# both page-relative, mirrored to public/ root. next.config.ts rewrites
# /app/{name}.json → /{name}.json for the auth'd routes.
$mobilePublic = Join-Path (Split-Path $mobileSrc -Parent) "public"
$rootAssets = @("sample_agents.json", "real_agent_frames.json")
foreach ($name in $rootAssets) {
  $src = Join-Path $mobilePublic $name
  if (-not (Test-Path $src)) { Write-Error "missing public asset in mobile repo: $src" }
  if ($DryRun) {
    Write-Host "would copy public\$name"
  } else {
    Copy-Item $src (Join-Path $webRoot "public\$name") -Force
  }
  $copied++
}

# Safety: verify no seam file got clobbered (they must remain tiny re-exports/shims).
foreach ($rel in $seamFiles) {
  $p = Join-Path $vendorRoot $rel
  if ((Test-Path $p) -and (Get-Item $p).Length -gt 4KB) {
    Write-Warning "seam file $rel is suspiciously large — did a copy clobber the web shim?"
  }
}

# ── Per-dir VENDOR.md manifests (regenerated on every sync) ─────────────────
# Extra notes per top-level vendored dir (kept across re-syncs).
$dirNotes = @{
  "glcharts" = @(
    "This is the app's ONLY glcharts copy (whole tree minus ``demo/``; the old standalone",
    "``src/glcharts`` vendor was deleted in Phase 2 so ``chartBridge`` / ``indicatorRegistry``",
    "are a single module instance shared by IndicatorLibraryPanel and GlChartPanel).",
    "",
    "- **Contract:** bars ``{ t, o, h, l, c, v }`` with ``t`` = unix seconds",
    "- **React entries:** ``react/GlChartView.jsx`` (bare chart), ``react/GlChartPanel.jsx`` (toolbar +",
    "  indicators + forecast overlays) — both client-only, no SSR (mount via ``next/dynamic``)",
    "- ``react/GlChartPanel.jsx`` resolves ``../../lab/forecastHostClient.js`` (seam shim) and",
    "  ``../../charting/react/useChartChrome.js`` (vendored) inside this tree",
    "- Selftest: ``node src/mobile/glcharts/glcharts.selftest.mjs`` (pure layers, node-runnable)"
  )
  "charting" = @(
    "Full Charts-workspace tree (Phase 3): ``react/ChartWorkspace.jsx`` (FlexLayout multi-pane,",
    "widget palette, workspace persistence), classic klinecharts ``ChartPanel`` stack, ``sources/*``",
    "(Kraken REST/WS, synthetic, ``/market/bars``), ``settings/*`` + ``workspaceStore.js`` (IndexedDB",
    "via ``kestrel/db.js``).",
    "",
    "- Mount client-only (``next/dynamic`` ``ssr: false``) — module tree touches window/localStorage/IndexedDB",
    "- ``sources/fromMarketBars.js`` resolves the ``dataserver.js`` + ``relay.js`` seams: on web the",
    "  LAN dataserver is honestly absent and the relay shim maps ``/market/bars`` → ``/api/market/bars``",
    "- ``sources/fromEquities.js`` resolves the ``kestrel/equitiesFeed.js`` seam (CapacitorHttp on mobile)",
    "- ``indicators/userIndicator.js`` pulls ``lab/forge/forgeIndicators.js`` + ``python/distillEngine.js`` (vendored, pure JS)",
    "- New deps this tree adopted: ``flexlayout-react`` (Decision 2 — locked), ``klinecharts`` (Classic engine;",
    "  lazy-loaded so cold paths never pay for it)"
  )
  "terminal" = @(
    "Instrument Terminal (Phase 3, plan item 19): FlexLayout dock shell, chrome, 12 analysis",
    "modules, MuseScript widget scaffold, fixtures (widget catalog), terminal CSS + flexlayout theme.",
    "",
    "- **Not vendored:** ``InstrumentTerminal.jsx`` + ``index.js`` (barrel) — they wrap mobile's",
    "  ``lab/StrategyStudio.jsx`` which web does not vendor. The web run-context host that feeds",
    "  ``InstrumentTerminalLayout`` is ``src/components/terminal/TerminalHost.tsx`` (mounted at ``/app/terminal``).",
    "- ``modules/*`` that need the local mederos_node (Cockpit, Leak Audit, Sizing, Regime, X-ray)",
    "  degrade honestly through ``kestrel/brokerLocal.js`` → ``dataserver.js`` seam (``no_local_node``).",
    "- ``kestrel/signalAlerts.js`` is a seam shim (web Notification API / honest ``queued_ui_only``).",
    "- Layout persists at ``mederos.terminal.layout.v2`` (localStorage) via ``shell/useTerminalLayout.js``.",
    "- Smoke selftest port: ``node scripts/check-terminal-smoke.mjs`` (from mobile ``__tests__/terminal.smoke.selftest.mjs``)."
  )
  "widgets" = @(
    "Unified flex-widget registry + palette (Phase 3, plan item 20) — single catalog for the",
    "terminal Add-panel modal and the Charts-workspace palette. ``standalone`` flags mark widgets",
    "that render meaningfully without a live strategy session; hosts show an honest placeholder",
    "for the rest."
  )
  "kestrel" = @(
    "Only the device-API-free pieces are vendored: infra (``db.js`` IndexedDB store, ``kraken.js``",
    "keyless public REST, ``usageEvents.js``, ``forecasterRating.js``) + the Phase 5 rank pipeline",
    "(``kestrelEngine`` / ``modelRegistry`` / ``scoreBars`` / ``encoder`` / ``channels`` /",
    "``forecastHead`` / ``rankFromFeatures`` — pure JS, no ONNX; model JSON ships at",
    "``public/models``) + explore state (``localReco`` / ``rankFeedCache`` / ``useRankPool`` /",
    "``exploreIntro`` / ``feedUtils`` / ``explain``) + trading math (``tradingBridge`` /",
    "``liveGate`` / ``riskEnvelope`` / ``portfolio`` / ``paperTrack`` / ``paperGate`` /",
    "``robinhood``) + the Phase 6 dossier plumbing (``companyNav`` pub/sub,",
    "``companyDossierSync`` hold-and-sync bar queue — its flush posts through the dataserver",
    "seam and degrades honestly on web).",
    "",
    "Phase 7 (plan item 34) turned ``brokerLocal.js`` + ``krakenTrade.js`` into SEAMS backed by",
    "the WEB PAPER BROKER (``_shims/paperBroker{Core,Store}``, localStorage, single-device):",
    "preview → approve → execute simulates fills against a local `$10k paper account priced",
    "off live public data (Kraken REST / ``/api/market/bars``), so Cockpit / Home /",
    "portfolioAggregate show real local positions. Real broker links + the node-compute",
    "efficacy suites stay honestly ``no_local_node``; a durable cross-device broker is blocked",
    "on relay account state. Everything Capacitor-flavored in this dir is a seam shim — see",
    "the seam list below."
  )
  "lib" = @(
    "Tiny portable helpers (promise timeout, Demo-data switch + hook, localStorage JSON store,",
    "motion-governor singleton). No device APIs."
  )
  "hooks" = @(
    "``useMediaQuery.js`` (plain matchMedia) + ``useCountUp.js`` (motion-governed count-up) —",
    "portable as-is."
  )
  "strategies" = @(
    "Strategy library (Phase 4, plan item 21): ``StrategyLibrary.jsx`` (distilled-logic cards:",
    "your inventory genomes ranked by held-out perf + the hand-authored seed shelf),",
    "``strategyLib.js`` (seed list + genome→card mapping), ``CodeCard.jsx`` (annotated,",
    "tokenized code card), ``MathFormula.jsx`` (KaTeX with graceful degradation — ``katex`` is",
    "dynamically imported; web adopted the dep + ``katex/dist/katex.min.css``).",
    "",
    "- Mounted at ``/app/strategies`` via ``src/components/library/StrategyLibraryHost.tsx``.",
    "- This is the CANONICAL distilled-logic library. Web Studio's strategy list",
    "  (``src/lib/studioStore.ts``) is a different store (runnable MuseScript sources) and",
    "  links here instead of duplicating this surface.",
    "- ``CodeCard`` explain-deeper: on-device LLM + dataserver Ollama are both seams on web",
    "  (canned-note fallback, honestly labeled)."
  )
  "social" = @(
    "Marketplace / certified social graph (Phase 4, plan item 22): ``StrategyFeed.jsx``,",
    "``socialGraph.js`` + ``lineage.js`` + ``certifiedCredential.js`` (pure graph/credential math),",
    "``follow.js`` (per-device localStorage follow edges), ``profile/CertifiedProfile.jsx``.",
    "",
    "- Mounted at ``/app/marketplace`` via ``src/components/social/MarketplaceHost.tsx``.",
    "- READS: ``social.js`` hits ``/social/*`` (same-origin); ``next.config.ts`` rewrites that to",
    "  ``/api/social/*`` where feed/authors are derived from the web Honest Leaderboard store",
    "  (``src/lib/socialBridge.ts``) — the same certified surface ``/leaderboard`` reads.",
    "- WRITES (publish/fork/rate): ``/api/social/*`` returns 503 ``durable_store_not_configured``",
    "  and the vendored UI degrades honestly (mobile offline contract). Durable social writes",
    "  are BLOCKED on Decision 6 (relay vs Firestore) — do NOT persist them to ``.data``."
  )
  "economy" = @(
    "Reasoning economy (Phase 4, plan item 23): ``credits.js`` wallet + ``contributions.js``",
    "earn-side + ``perspectiveDensity.js`` novelty pricing + ``inventory.js`` owned artifacts +",
    "``ReasoningEconomy.jsx`` / ``InventoryView.jsx``.",
    "",
    "- Mounted at ``/app/economy`` via ``src/components/economy/EconomyHost.tsx``.",
    "- DEVICE-LOCAL WALLET: on web ``getDataserverBase()`` (seam) is null, so the wallet/ledger/",
    "  contributions live in this browser's IndexedDB (``kestrel/db.js``) — clearly labeled in",
    "  the host. The server-authoritative wallet path stays dormant until Decision 6 picks a",
    "  durable backend; ``auth.js`` is a seam that reads the web session."
  )
  "components" = @(
    "Vendored: ``Skeleton.jsx`` (loading skeletons) + the Phase 6 company surface",
    "(``CompanyDossier.jsx`` + ``EdgarExplorer.jsx`` — mounted at ``/app/company`` via",
    "``src/components/company/CompanyHost.tsx``; both read the dataserver seam, which the",
    "host scopes to the same-origin ``/api/edgar`` SEC proxy while mounted — the LAN",
    "dataserver stays disabled on web) + the Phase 5 explore feed",
    "(``RankSwipeFeed`` / ``RankExploreGrid`` / ``RankSlideCard`` / ``SwipeCarousel`` /",
    "``IntuitionSlide`` / ``RecoHud`` / ``ContribChart`` / ``OfflineEmpty``) + trade/order",
    "sheets (``TradeSheet`` / ``DeployBookSheet`` / ``NumberField`` — preview/execute degrade",
    "honestly with no local node). ``SignInSheet.jsx`` is a WEB SHIM (web auth session card)",
    "— see the seam list below. ``NumberField``/``SymbolPicker``'s direct ``@capacitor/haptics``",
    "import resolves to ``_shims/capacitorHaptics.ts`` via next.config.ts resolveAlias."
  )
  "iap" = @(
    "``IapPaywall.jsx`` is a WEB SHIM only (RevenueCat is device-only; web billing lives at",
    "``/billing``, credit packs blocked on Decision 6). Nothing in this dir is a mobile copy."
  )
  "python" = @(
    "Pure-JS distill/backtest stack + the routed Python backends (Phase 5 pulled these in for",
    "the swarm's forward-sim; Phase 6's Lab/Forge/DistillBench run on the same router —",
    "including the in-browser js-exact vs CPython ``parityCheck`` gem). ``pyRouter.js`` prefers",
    "the lightest tier: ``jsExactRuntime`` (pure JS, works everywhere) → ``pyodideRuntime``",
    "(CPython WASM worker; loads the SAME ``mobile_sim.py``/``mobile_distill.py`` from the",
    "static ``/pysrc`` mirror the sync script copies into ``public/pysrc`` — this is what runs",
    "the swarm forward-backtest in-browser) → ``dataserverRuntime`` (LAN server — honestly",
    "absent on web via the dataserver seam)."
  )
  "swarm" = @(
    "Swarm builder + scheduler (Phase 5, plan item 24): ``SwarmView.jsx`` graph builder,",
    "``swarmStore.js`` ensemble store (localStorage), ``swarmExec.js`` + ``kestrelForwardSim.js``",
    "execution/forward-sim, ``swarmScheduler.js`` cadence runner, mycelium canvas.",
    "",
    "- Mounted at ``/app/swarm`` via ``src/components/swarm/SwarmHost.tsx`` (client-only).",
    "- Phase 7 (plan item 32): a singleton IN-TAB scheduler",
    "  (``src/lib/swarmForegroundScheduler.ts``, started by the /app layout's AppRuntime)",
    "  drives ``swarmScheduler.runOnce()`` on cadence from a Web Worker heartbeat, so ticks",
    "  survive background-tab timer throttling — runs while any Mederos tab is open.",
    "  Closed-tab execution needs a relay-side job runner (``trueBackgroundStatus()`` — the",
    "  honest stub the host badge reads); @capacitor/background-runner has no web analogue.",
    "- ``swarmSignalBridge.js`` is pure functions (no I/O) — vendored as-is, NOT stubbed.",
    "- ``sync/swarmOrderRelay.js`` is local-first (localStorage ring buffer); its mesh push is",
    "  a silent no-op with no hub (dataserver seam is null on web).",
    "- ``kestrel/notifications.js`` is a seam shim (Phase 7: service-worker delivery when",
    "  permission is granted, honest false otherwise).",
    "- Trade paths (krakenTrade/DeployBookSheet) run against the Phase 7 WEB PAPER BROKER:",
    "  preview → human approve → simulated fill (``dry_run: true``, ``PAPER-…`` txids). Real",
    "  live routing stays impossible on web — no real venue exists without the local node."
  )
  "home" = @(
    "Home dashboard (Phase 5, plan item 25): ``HomeView.jsx`` (net worth, holdings, analytics,",
    "swarm + economy cards), ``ForwardBacktestHero.jsx`` / ``ForwardBacktestTheater.jsx``",
    "(honest walk-forward theater), ``portfolioAggregate.js``.",
    "",
    "- Mounted at ``/app`` via ``src/components/home/HomeHost.tsx``.",
    "- Phase 7 (plan item 34): ``portfolioAggregate`` leg 0 reads the WEB PAPER BROKER through",
    "  the ``kestrel/brokerLocal.js`` seam — real local paper positions render once any",
    "  simulated fills exist. Otherwise the Demo-data switch (``lib/demoData.js``) drives the",
    "  labeled demo book, and demo-off with no paper trades shows the honest empty state.",
    "- ``lib/accountDialog.js`` is a pub/sub channel — the web host subscribes and renders",
    "  a web account card (session via /login) instead of mobile's AccountDialog."
  )
  "desktop" = @(
    "``useResizablePanel.js`` + ``ResizeHandle.jsx`` — pure pointer/localStorage resize helpers",
    "used by RankExploreGrid. No device APIs."
  )
  "lab" = @(
    "Phase 1 Studio parity panels (Optimize/Debugger/ReportCard/Ledger/TruthReport/",
    "IndicatorLibrary/Autoresearch/Repaint — hosted inside web Studio) + Phase 2 MuseNotebook +",
    "Phase 6 Lab & Forge (plan items 27-28).",
    "",
    "- **Lab** (``StrategyLab.jsx`` + FitArena/FanChartTheater/KestrelRunTheater/DistillBench/",
    "  OosPerf/SavedRules/MuseLabPanel) mounts at ``/app/lab`` via",
    "  ``src/components/lab/LabHost.tsx`` (client-only). Server-run controls degrade honestly:",
    "  ``labClient.js``/``pingDataserver`` see the null dataserver seam, so the Lab runs",
    "  ON-DEVICE via ``onDeviceRun.js``/``distillRunner.js`` → ``python/pyRouter.js``",
    "  (Decision 3 LOCKED: js-exact first, Pyodide tier via the static ``/pysrc`` mirror,",
    "  dataserver tier honestly absent).",
    "- **Forge** (``forge/ForgePage.jsx``) mounts at ``/app/forge`` via",
    "  ``src/components/forge/ForgeHost.tsx``; swarm/lab hand seeds over in sessionStorage.",
    "  ``forge/forgeLlm.js`` routes through the onDeviceLlm seam → honest manual mode.",
    "- 3D theaters (``KestrelRunTheater``/``KestrelDistillGlobe``) render through the vendored",
    "  ``glgraph`` tree (three.js — client-only dynamic import).",
    "- Seam shims in this dir: ``haptics.js``, ``muse-runtime.js``, ``museRuntimeClient.js``,",
    "  ``forecast-host-runtime.js``, ``forecastHostClient.js``, ``onDeviceExplain.js``."
  )
  "glgraph" = @(
    "WebGL 3D constellation engine (Phase 6, plan items 27/30): three.js scene/orbit/picking,",
    "``d3-force-3d`` layout in a module Web Worker (``layout/layout.worker.js`` —",
    "``new Worker(new URL(...))``, bundled by Next), ``troika-three-text`` labels.",
    "",
    "- Consumers: EdgarExplorer + CompanyDossier 3D mode (``/app/company``), Lab theaters.",
    "- CLIENT-ONLY: import through ``next/dynamic`` ``ssr: false`` hosts (three touches window/WebGL).",
    "- New deps this tree adopted (Decision 4, on first use): ``three``, ``troika-three-text``,",
    "  ``d3-force-3d`` — all lazy-loaded behind dynamic imports so cold paths never pay for them.",
    "- Selftest: ``node src/mobile/glgraph/glgraph.selftest.mjs`` (pure normalize/appearance layers)."
  )
  "minigames" = @(
    "Full minigames surface (Phase 6, plan item 31): vignette catalog/generator/grader +",
    "feed ``MiniGameCard`` + link-based calibration Duels (``duel/*``). LOCAL-FIRST by design:",
    "duels are commit/verify/score over a shareable token — both sides recompute locally,",
    "no server. Mounted at ``/app/games`` via ``src/components/games/GamesHost.tsx`` (the",
    "host builds ``shareBase`` from the page origin so duel links deep-link back to /app/games).",
    "``annotations.js`` posts to the dataserver/auth seams — honest local-only on web."
  )
  "sync" = @(
    "Device-mesh transport + consumers. All LOCAL-FIRST: rows land in localStorage/IndexedDB",
    "first; the hub push is best-effort and silently absent on web (dataserver seam is null,",
    "so ``getSyncStatus()`` reports no hub).",
    "",
    "Phase 7 (plan item 36) settled the web mesh story: the RELAY is the web's mesh for",
    "reads — device pairing + ``/api/relay/*`` already serve mesh bars (``/app/charts`` 'via",
    "mesh') and venue status (``/app/brokerage``) from a paired home machine. This dir's hub",
    "PUSH (deviceMesh/kestrelSync/swarmOrderRelay rows to a LAN dataserver) has no relay",
    "endpoint yet, so cross-device row sync stays an honest local-only no-op — blocked on",
    "relay work (Decision 6 adjacent), never faked. ``computeRouter.js`` (Phase 6) routes",
    "distill jobs the same way: local pyRouter tiers on web, mesh offload honestly unavailable."
  )
}

if (-not $DryRun) {
  $stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
  $byDir = $files | Group-Object { Split-Path $_ -Parent }
  # Only real directories get a VENDOR.md — root-level vendored files
  # (feedSource.js, drawerMotion.js) are documented in src/mobile/VENDOR.md.
  $topDirs = $files | Where-Object { ($_ -split "\\").Count -gt 1 } |
    ForEach-Object { ($_ -split "\\")[0] } | Sort-Object -Unique
  foreach ($top in $topDirs) {
    $dirFiles = $files | Where-Object { ($_ -split "\\")[0] -eq $top } | Sort-Object
    $seamsHere = $seamFiles | Where-Object { ($_ -split "\\")[0] -eq $top } | Sort-Object
    $md = @()
    $md += "# src/mobile/$top (vendored)"
    $md += ""
    $md += "Copied from ``kalshai/mobile/src/$top`` by ``muse-script/tools/sync-mobile-views.ps1`` (last sync $stamp)."
    $md += "Do NOT edit vendored files here — fix in the mobile repo and re-run the sync."
    $md += "See WEB_SURFACE_PARITY_PLAN.md §2.2 for the vendor-tree + shim-seam architecture."
    $md += ""
    if ($dirNotes.ContainsKey($top)) {
      $md += $dirNotes[$top]
      $md += ""
    }
    $md += "## Vendored files"
    $md += ""
    foreach ($f in $dirFiles) { $md += "- ``$($f -replace '\\','/')``" }
    if ($seamsHere.Count -gt 0) {
      $md += ""
      $md += "## Seam files (WEB SHIMS in this dir — never re-copied)"
      $md += ""
      foreach ($f in $seamsHere) { $md += "- ``$($f -replace '\\','/')`` -> re-exports ``src/mobile/_shims/*``" }
    }
    $mdPath = Join-Path (Join-Path $vendorRoot $top) "VENDOR.md"
    Set-Content -Path $mdPath -Value ($md -join "`n") -Encoding utf8
  }
}

Write-Host "sync-mobile-views: $copied file(s) $(if ($DryRun) { 'would be copied' } else { 'copied' }), $skipped skipped, into $vendorRoot"
