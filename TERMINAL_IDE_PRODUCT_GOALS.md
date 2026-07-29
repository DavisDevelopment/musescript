# Trading Terminal / Strategy IDE — Productization Goals (Cursor)

**Date:** 2026-07-28
**Vision:** the **highest-value trading terminal + strategy IDE on the market** — not because it
promises alpha (nobody honest can), but because it's the only one that **tells the user the truth
about their strategy** and gives them pro-grade, uncertainty-aware analysis without the false
confidence every other terminal sells.

**The thesis we just earned the right to say:** we spent a week building forecasting substrates
(Elliott Wave, regime, volume-auction), a co-evolution engine, and a benchmark — and then built a
*validated* measurement instrument that proved none of them carry tradeable edge. That negative is the
product. **"We show you when your strategy is a coin flip"** is now backed by controls that provably
reject noise, detect real edge, and collapse under label-shuffle. No competitor can say that.

**The reframe for this whole doc:** every subsystem below had ~zero alpha value and enormous PRODUCT
value. A forecaster with no edge is still a gorgeous, honest chart overlay. A backtester that found
nothing is the most trustworthy one on the market. We ship the tooling and the rigor.

---

## Where the pieces live (integration map)

- **Forecast substrates + instrument + rig:** `muse-lab/muse-script/musescript/{ew,evo,ew/mcmc,ew/auction,evo/rigor}` (Haxe; dual-compiles interp/JS/WASM/JVM).
- **The IDE / terminal frontend:** the app (`kalshai/mobile`) — Strategy Studio, `mobile/src/glcharts` (WebGL2 chart engine), the notebook + debugger. Also Electron desktop distribution.
- **Marketing surface:** `mederos-web`.
- **Language:** MuseScript — strategies already read forecasts via `SProj(name, field)` / host reductions.
- **Prototype:** `Forecast Studio` (published artifact) — the Forecast Panel, 80% built.

Enabler that gates several initiatives: **WASM-compile the forecast hosts** so they run in the user's
browser/desktop on their own chart (the hosts are Haxe; `DetRng`/`DetMath` are already byte-identical
WASM-ready; `glcharts` + the museRuntime live-demo widget are the compile/runtime pattern to follow).

---

## Ground rules

- **Honesty is the product, not a disclaimer.** Every feature that reports performance MUST route
  through the hardened instrument (DSR / PBO / min-trades / purge-embargo / null baseline). A number
  shown without its honest verdict is a bug.
- **Uncertainty-first.** Forecast overlays show bands + alternates + invalidation + entropy, never a
  single dogmatic line. "PROJECTED — not confirmed" is a permanent tag.
- **Reproducible.** What the user backtests is bit-identical to the browser preview and live execution
  (byte-identical determinism). Surface it as a guarantee.
- **Boundaries:** these are product initiatives spanning muse-script (Haxe) + the app frontend. Land
  per-initiative. Don't regress the hardened instrument or the forecast-host interface — build on them.

---

## INITIATIVE 1 — "The Honest Backtest" (Truth Report)  ·  PRIORITY 0, the flagship

**The single most differentiating feature in the product.** When a user backtests a MuseScript
strategy in the IDE, they don't just get a Sharpe and an equity curve — they get a **Truth Report**:

- [x] **1.1 Wire the instrument into the IDE backtest flow.** Every backtest run through `Fitness` +
  `evo/rigor` produces: beats-null? (vs the strongest cheap baseline, per instrument), **DSR-adjusted
  Sharpe** (deflated by the number of strategy variants the user has tried this session — track the
  trials count), **PBO** (probability-of-backtest-overfitting), **OOS-held** with purge/embargo, and
  the **min-trades** sanity gate. *Accept:* a 1-trade "great Sharpe" strategy is flagged red, not
  celebrated; a genuinely robust one clears all gates.
  → Studio Run path attaches `truthReport` via MuseRuntime (BH null, DSR+min-trades+CI+beats-null).
    Purge/embargo OOS via `honestOos` + live session-cloud PBO landed (see TRUTH_REPORT_IDE_HANDOFF.md).
- [x] **1.2 Traffic-light verdict UI.** A single at-a-glance verdict (Robust / Fragile / Coin-flip /
  Overfit) with the drill-down of which gate it failed and WHY, in plain language ("your Sharpe of 2.1
  drops to 0.3 once we account for the 40 variants you tried — that's noise-mining").
  → `kalshai/mobile` `TruthReportPanel.jsx` in Strategy Studio.
- [x] **1.3 "Trials" tracking.** Count how many strategy variants the user has backtested and deflate
  accordingly — the anti-p-hacking feature. *Accept:* the more you tweak-and-retest, the higher the bar.
  → `studioTrialsSession.js` (sessionStorage fingerprints) → `nTrials` on each run.
- [x] **1.4 Null-baseline exemption fix.** The min-trades gate currently sends buy-and-hold (a legit
  1-trade baseline) to −∞; exempt low-trade *nulls* or compare buy-and-hold on return, so the baseline
  stays a fair bar. (Carries over from the hardening Bucket A/I list.)
  → Landed in muse-script: `Fitness.scoreNullBaseline` / `BasketFitness.scoreNullBaseline`; CorpusEvoRun
  BH OOS uses the exemption. Truth Report contract: `evo/rigor/TruthReport.hx` + `TrialsSession.hx`.
  IDE wiring / traffic-light UI / share card: see `TRUTH_REPORT_IDE_HANDOFF.md`.
- [x] **1.5 Shareable Truth Report.** Export the verdict as a shareable card (ties to the marketing
  moat — users sharing "my strategy passed the Honest Backtest" is organic proof of the differentiator).
  → PNG share card + `mederos.truthReport.v1` JSON (seed/digest stamped) in `TruthReportPanel.jsx`.

**Why it wins:** TradingView, MT5, NinjaTrader all let users fool themselves. This is the one feature
that makes the terminal *trustworthy*, and it's the literal embodiment of the brand.

## INITIATIVE 2 — "Forecast Panel" (Probabilistic Overlays)  ·  PRIORITY 1

Productize `Forecast Studio` into the live terminal chart. The forecast hosts become premium,
toggleable, honest overlays on the user's own instrument.

- [x] **2.1 WASM-compile the forecast hosts** (`Lattice`/`Regime`/`Auction`) so they run in-browser on
  the user's chart, byte-identically to the JVM/backtest. *Accept:* same seed+bars → same cloud in the
  browser as in the backtest (extend the parity gate to the compiled hosts).
  → Landed: `ForecastHostRuntime` + `ForecastHostParityDump` + `tools/forecast_host_parity_ci.*`
  (see `musescript/ew/FORECAST_HOST_WASM.md`). Haxe→JS browser module (museRuntime pattern);
  JVM↔node bit-identity proven for all three hosts.
- [x] **2.2 EW overlay** — the *fan of alternate counts* (opacity ∝ posterior mass) + invalidation
  line + entropy readout. Honest by design: shows the ambiguity, never one dogmatic count.
  → `FC_EW` in `mobile/src/glcharts/forecast/` via lattice `ensembles` + `counts`.
- [x] **2.3 Regime overlay** — volatility-regime background shading + forward predictive cone + a
  "regime state" badge (calm/volatile + confidence).
  → `FC_REGIME`; live MCMC debounced + reduced sampler; trailing wash uses current regime.
- [x] **2.4 Auction overlay** — volume-profile histogram + value-area + POC + balance/discovery state.
  → `FC_AUCTION` + host `state.bins:[{price,vol}]`.
- [x] **2.5 Render via `glcharts`** (the Forecast Studio prototype is the visual spec; port its Canvas
  overlays into the WebGL engine). Each overlay carries the "PROJECTED — not confirmed" honesty tag.
  → Canvas2D paint on the GL overlay layer (same path as GeomViz); tagged on every draw.

**Why it wins:** these are features competitors sell à la carte and present dogmatically. Ours are
pro-grade AND honest (entropy, alternates, invalidation) — the same rigor differentiator, visualized.

## INITIATIVE 3 — "Strategy Optimizer" (honesty-gated evolution)  ·  PRIORITY 2

Expose the co-evolution rig as a user feature — with the Honest Backtest as its gate.

- [x] **3.1 "Evolve this strategy" action.** User writes a MuseScript skeleton (with holes / tunable
  params), the evolver searches variants. Uses the existing `CorpusEvoRun` / `Variation` / `Fitness`.
  → Host API: `MuseRuntime.optimize` / `evolve` (`HonestOptimize` + `PlanRunner.trialSweep`).
    Studio: `StudioOptimizePanel` + `optimizeStrategy` client.
- [x] **3.2 Every candidate passes the Truth Report gate** (Initiative 1) — so the optimizer surfaces
  ONLY non-overfit results, or honestly reports "nothing beat the null." *Accept:* the optimizer can
  return "no robust strategy found" — and that's a feature, not a failure.
  → Gate: acceptVerdicts default `Robust`+`Fragile`; Overfit/Coin-flip never ship.
- [x] **3.3 Forecast-aware strategies.** Let evolved/authored strategies read forecast overlays as
  first-class inputs (`forecast("regime").entropy`, `forecast("auction").breakout_prob`, EW invalidation
  distance) — the co-evolution boundary already supports this; surface it in the language + Studio.
  → `ProjectionProvider` aliases (`breakout_prob`, `poc`); `MuseRuntime.forecastFields()`;
    doc `musescript/ew/FORECAST_STRATEGY_INPUTS.md`. Full overlay UI stays Initiative 2.

**Why it wins:** "automated strategy search that refuses to lie to you" is a category nobody occupies.

## INITIATIVE 4 — "Backtest == Live" (reproducibility guarantee)  ·  PRIORITY 2

Turn the byte-identical determinism foundation into a trust feature.

- [x] **4.1 Determinism badge/proof** — surface that the strategy's backtest, browser preview, and live
  execution are bit-identical (the `DetParityDump`-style proof, productized). *Accept:* a user can
  verify their backtested equity curve reproduces exactly in the live-preview engine.
  → `DeterminismProof.hx` + `MuseRuntime.proveDeterminism`; Studio `DeterminismBadge`.
    `DetParityDump` foundation digest + cross-engine equity proof; `TestReproDeterminism`.
- [x] **4.2 Seeded, reproducible runs** — every backtest/optimization is seed-stamped and re-runnable
  to the bit. Ties to the honest-report shareability (a shared report is verifiable).
  → `ReproStamp.hx` on `TruthReport`, `PlanRunner`, `HonestOptimize`, `OptimizeResult`;
    share cards + report cards carry `repro` for bit-identical re-run.

**Why it wins:** "what you test is what you trade" kills the #1 fear of systematic traders — that the
backtest lied about the fills/logic. Reproducibility is trust.

## INITIATIVE 5 — "Strategy Report Card / Honest Ledger"  ·  PRIORITY 3

The benchmark + scoreboard as a product surface.

- [x] **5.1 Report Card** — per-strategy: capture/skill vs null, profit vs baseline, per-instrument
  robustness, seed-robustness, universe-robustness — the benchmark runners' output as a clean UI.
  → `ReportCard.hx` + `MuseRuntime.buildReportCard` / `seedRobustnessSweep`; Studio `ReportCardPanel`.
    Single-tape + optional seed sweep landed; multi-instrument universe is an extension slot.
- [x] **5.2 The Ledger** — a running, honest record of what the user's strategies actually did OOS
  (GOs and NO-GOs equally), reinforcing the "we keep you honest" relationship over time.
  → `HonestLedger.hx` entry contract + Studio `honestLedger.js` (localStorage) + `HonestLedgerPanel`.

**Why it wins:** it operationalizes the brand ("honest NO-GOs are the moat") into a recurring surface
the user returns to.

---

## Priority summary

| P | Initiative | The one-liner | Biggest lift |
|---|---|---|---|
| 0 | Honest Backtest | "we tell you when your strategy is a coin flip" | wire instrument → IDE flow + verdict UI |
| 1 | Forecast Panel | pro-grade honest chart overlays | WASM-compile the hosts + glcharts port |
| 2 | Strategy Optimizer | search that won't ship overfit junk | gate evolution by Initiative 1 |
| 2 | Backtest == Live | reproducibility as trust | surface the determinism proof |
| 3 | Report Card / Ledger | honesty as a recurring surface | benchmark output → UI |

**Do Initiative 1 first.** It's the differentiator, it's mostly wiring (the instrument exists), and
every other initiative (optimizer, report card) depends on it. Initiative 2 is the visual wow and the
Forecast Studio prototype is the spec — WASM-compiling the hosts is the real work there.

**North star:** a trader opens the terminal, drops on an EW/regime/volume overlay that's honest about
its own uncertainty, writes or evolves a MuseScript strategy, backtests it, and gets a **Truth Report**
that either earns their trust or saves their account — reproducibly, in-browser, bit-identical to live.
That's a terminal worth paying for, and nobody else is building it.
