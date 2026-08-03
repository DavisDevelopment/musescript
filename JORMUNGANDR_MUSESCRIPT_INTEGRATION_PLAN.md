# Jormungandr ↔ MuseScript Integration Plan

*Status: P2 landed (2026-08-03). D1 locked = Desktop/browser-only Muse execution.*
*Home: muse-script (brain). Body lives in `kalshi-ai-advisor/python/worldfeed` + Desktop `mobile/src/world` + muse_fincog Causal Sim. Cross-link: `kalshi-ai-advisor/python/WORLD_DATA_PLATFORM.md` §11.*

---

## Vision

**Jormungandr is the body** — a geographic / transit / contagion surface: live World-Data events, flights, shipping corridors, and Causal Sim activation fans scrubbed across the map. **MuseScript is the brain** — Haxe programs, Wasm `on_bar`, honesty-gated evolution, ForecastHost reductions, and Truth/Leaderboard machinery that light up *when* and *because* the world moves. The integration makes shocks become strategy context, regimes become evolution fitness worlds, and calibrated forecasts become map overlays — without ever monetizing P&L vanity or faking certainty when a seed is unmapped.

---

## Architecture (dataflow)

```mermaid
flowchart TB
  subgraph Body["Jormungandr body"]
    EXT["External sources<br/>GDELT / OpenSky / AIS / Wiki…"]
    WF["WorldFeedStore + digestion<br/>/world/feed · flights · vessels"]
    SEED["sim_seed hint<br/>observable · dir · mag · region"]
    BRIDGE["sim_bridge.py → world-bridge-cli<br/>Propagator MC + series fans"]
    MAP["Desktop WorldView<br/>MapLibre + deck.gl + scrubber"]
    EXT --> WF --> SEED --> BRIDGE
    WF --> MAP
    BRIDGE -->|run.nodes[].series| MAP
  end

  subgraph Adapter["World→Muse adapter (new)"]
    ALIGN["WorldTapeBuilder<br/>align market bars ⊕ activation(t)"]
    CTX["WorldContext envelope<br/>run_id · scenario_key · sim_seed · fan"]
    ALIGN --> CTX
  end

  subgraph Brain["MuseScript brain"]
    RT["MuseRuntime<br/>run / runPanel / runWasm / evolve"]
    FH["ForecastHostRuntime<br/>regime · auction · lattice · world?"]
    TR["TruthReport · ReportCard · Ledger"]
    LB["Honest Leaderboard<br/>scenario-keyed entries"]
    RT --> TR --> LB
    FH --> RT
  end

  subgraph Overlay["Signals back onto the body"]
    SIG["Strategy plots / signals<br/>choropleth tint · corridor pulse"]
    FC["Calibrated forecast claims<br/>p · Brier provenance"]
    SIG --> MAP
    FC --> MAP
  end

  BRIDGE --> ALIGN
  WF --> ALIGN
  CTX --> RT
  CTX --> FH
  RT --> SIG
  FH --> FC
  TR -.->|"verdict never P&amp;L"| Overlay
```

### One-sentence contract

World events produce **honest** Causal Sim fans; fans + market tape become a **WorldContext**; MuseScript runs / evolves / forecasts against that context and publishes **overlays + Brier-ranked claims** back to the map — skips stay skips.

---

## What already exists (verified seams)

| Layer | Location | Reuse as-is |
| --- | --- | --- |
| Feed / events / `sim_seed` | `WORLD_DATA_PLATFORM.md` §4; `digestion.py` | Event contract + nullable shock hint |
| Simulate + persist | `POST /world/simulate`, `GET /world/simulate/runs{,/id}` | Ensemble seeds, counterfactual, `run_id` |
| Series fans | muse_fincog `WORLD_SIM_BRIDGE.md`; Desktop `jormungandrSimSeries.js` | Scrub by engine `t` / index — never synthesize peaks |
| Desktop client | `worldSimClient.js`, `WorldSimPanel.jsx`, `WorldView.jsx` | Status / simulate / history / remediation / n_runs |
| Muse public surface | `MuseRuntime` (~24 APIs), `ForecastHostRuntime.kinds() = regime\|auction\|lattice` | Browser/Desktop lab already loads via `museRuntimeClient.js` |
| Aux series | `Bar.data` + `HarnessContext.pushAuxData` | Causal injection of world columns into strategies |
| Params | `opts.params` after `@param` registration | Map `sim_seed.magnitude` / regime knobs without new AST |
| Constitution | `MEDEROS_CONSTITUTION.md`, SPEC_CAUSAL_SIM §7–8 | Brier / calibration currency; never P&L as clout |

**Gap today:** zero Muse↔World coupling in code search. Desktop runs Contagion; Lab runs Muse — parallel organs, no shared nerve.

---

## Seams (APIs / types to add or reuse)

### 1. `WorldContext` envelope (shared JSON, versioned)

Carried client-side and optionally persisted beside `sim_runs`:

```ts
type WorldContext = {
  schemaVersion: 1;
  scenarioKey: string;          // stable: hash(event_ids|seeds|remediation|magMult)
  runId: string | null;         // /world/simulate/runs/{id}
  eventIds: string[];
  simSeeds: SimSeed[];          // worldfeed_event shape
  seriesMeta: SeriesMeta;       // horizon_days, n_steps, dt, fields
  fan: {
    tDays: number[];
    nodes: Array<{
      id: string;
      observable: string;
      mean: number[];           // length == tDays
      p50?: number[];
      p90?: number[];
      pExceed?: number[];
    }>;
  };
  controls: {
    seed: number;
    seeds?: number[];
    nRuns: number;
    counterfactual: boolean;
    remediation: boolean;
    magnitudeMultiplier: number;
  };
  generatedAt: string;          // ISO-8601
};
```

**DoD for type:** Desktop can build this from an existing `sim` outcome + `extractSimSeries` without a second simulate call.

### 2. `WorldTapeBuilder` — bars ⊕ fan → Muse bars

Reuse `Bar.data` aux keys (no AST change for MVP):

| Aux key | Meaning |
| --- | --- |
| `world_act_<nodeId>` | \|activation\| mean at aligned step |
| `world_p90_<nodeId>` | upper fan (optional) |
| `world_shock` | signed shock intensity active on this bar (`dir * mag` decayed or stepped) |
| `world_regime` | discrete label 0..K−1 from dominant node / category |

**Alignment modes** (open decision — see below):

- **A. Timestep tape** — one Muse bar per `tDays[k]`; OHLCV from nearest market bar or synthetic close from a chosen observable.
- **B. Calendar splice** — real market bars keep their clock; fan values are *as-of* joined (no lookahead: value at bar time is last sim sample with `t ≤ bar.time`).

Builder lives first in Desktop (`mobile/src/world/worldTapeBuilder.js`) with a twin contract doc in muse-script; promote to Haxe only if JVM evo needs the same bits.

### 3. MuseRuntime opts / thin wrappers (reuse > invent)

| Call | Extension |
| --- | --- |
| `run(source, bars, opts)` | `opts.params` ← `{ sim_mag, sim_dir, region_code, … }`; bars already carry aux |
| `runWasm(...)` | Same bars; scrubber can step Wasm session bar-by-bar as user drags `scrubT` |
| `evolve` / `optimize` | `opts` gains `worldContext` metadata stamped into `repro` + Truth Report meta |
| `ledgerEntryFromTruth` | Pass `tape: scenarioKey`, `id: runId` |
| `evaluateLeaderboardEntry` / `rankLeaderboard` | Entry gains optional `scenarioKey` / `worldRunId`; host filters field before rank |

**New optional facade** (JS first, Haxe later if needed):

```js
// proposed: mobile/src/world/worldMuseBridge.js
runUnderWorld(source, worldContext, marketBars, opts)
evolveUnderWorld(source, worldContext, marketBars, opts)
forecastFieldsUnderWorld(kind, worldContext, marketBars, opts)
```

Returns Muse result + `{ world: { scenarioKey, runId, alignment } }` for overlay paint.

### 4. ForecastHostRuntime — world-conditional clouds

Three options (pro/con below). Preferred **direction** without locking:

- Keep `kinds() = regime|auction|lattice` for market hosts.
- Add **adapter path**: materialize aux-enriched bars, then call existing `forecast(kind, bars, opts)` with `opts.seed = worldContext.controls.seed`.
- Optionally later: `kind: "world"` that emits clouds keyed by Causal Sim node ids (Brier-aligned to fincog claims).

Map overlay uses ForecastHost `clouds` / Muse `chart` commands → deck.gl layers (`jormungandr-muse-signals`, `jormungandr-muse-forecasts`).

### 5. Sim scrubber ↔ Wasm / debug stepping

- On scrub change: `WorldMuseBridge.signalAt(t)` → current aux row + optional `MuseDebugSession.step()` / Wasm host tick for the bar that corresponds to `t`.
- P0 can skip debug and only **re-run** on scrub end (debounce) — wow without stepper plumbing.

### 6. Backend optional route (P1+)

```http
POST /world/muse/context
{ "run_id": "...", "alignment": "calendar|timestep", "symbol": "SPY", "bars": [...] }
→ { worldContext, bars: MuseBar[] }
```

Keeps Desktop honest offline (builder local) while Lab/web can share server-built tapes. Does **not** execute Muse on the Python node (Constitution privacy: strategy source stays on client — Article III.6).

### 7. Leaderboard / truth dual-surface keys

```ts
type WorldLeaderboardEntry = LeaderboardEntry & {
  scenarioKey: string;
  worldRunId?: string;
  eventIds?: string[];
  calibClaims?: Array<{ node: string; p: number; resolvesOn: string }>; // Brier path
};
```

Rank **within scenario field** first; cross-scenario vanity ranks are forbidden.

---

## Phased roadmap

### P0 — Spike: “brain lights up” (minimal wow)

**Goal:** Click a World event → Simulate → Run a stock Muse strategy on world-augmented bars → see a signal layer + Truth chip on the World dock.

| Work | Owner surface |
| --- | --- |
| `WorldContext` builder from live `sim` outcome | Desktop `world/` |
| `worldTapeBuilder` (pick one alignment; ship behind flag) | Desktop |
| `worldMuseBridge.runUnderWorld` wrapping `museRuntimeClient` | Desktop |
| WorldSimPanel: **Run Muse** button + truth verdict pill | Desktop |
| deck overlay: plot last signal / equity delta tint on affected countries | Desktop |
| Sample strategy `.ms` using `world_shock` / aux series (docs + seed file) | muse-script `examples/` or `musescript/evo` seed |

**DoD**

- [x] Offline mock sim path still works; Muse run fails honestly if runtime missing.
- [x] Aux join never lookahead (parity selftest: shuffle future fan → unchanged past bars).
- [x] Truth Report attached; UI shows **verdict**, not Sharpe-as-headline.
- [x] One recorded GIF/scripted demo: event → fan scrub → Muse overlay. *(Playwright: `tests/world-sim.spec.js` Light Muse path; Desktop click path below.)*

**D1 resolved:** Muse executes in the Desktop/browser client only for P0–P1 (`museRuntimeClient` / `worldMuseBridge.runUnderWorld`). No strategy source upload to `/world/*`.

### P1 — Calibrated world-conditional strategies

**Goal:** Strategies are *conditional* on regime; forecasts scored on Brier when claims resolve.

| Work | Notes |
| --- | --- |
| Persist `scenarioKey` on Honest Ledger entries | Lab + World ✓ |
| Wire ForecastHost on world tape; paint p-clouds on map nodes | Desktop ✓ (adapter regime/auction + fan claim cones) |
| Optional `POST /world/muse/context` | Deferred — D1 client-only builders suffice for P1 |
| Pre-commitment calibration beat on World (expected verdict before Run) | Desktop ✓ |
| Resolve fincog Forecast claims → Brier rollup surfaced next to contagion panel | Desktop ✓ |

**DoD**

- [x] Same `scenarioKey` + seed → bit-identical Muse equityDigest (proveDeterminism).
- [x] Leaderboard evaluate filters by `scenarioKey`; cross-field rank disabled.
- [x] Skip reasons (`observable_unmapped`, …) still visible — Muse does not invent fans.

**Landed (2026-08-03):** Desktop `worldMarketTape` (SPY calendar join + honest synth badge), `worldCalibration` Brier chips, `forecastFieldsUnderWorld` + `jormungandr-muse-forecasts` layer, ledger/leaderboard `scenarioKey`, plan D1 unchanged (no Python Muse execute).

### P2 — Evolution / search under Jormungandr regimes

**Goal:** `evolve` / corpus search fitness = Truth skill **under** a fixed WorldContext (or small ensemble of contexts).

| Work | Notes |
| --- | --- |
| `evolveUnderWorld` multi-context holdout | At least 1 train scenario + 1 embargoed scenario ✓ |
| Regime library: conflict / outbreak / fx-shock seed packs | From feed categories ✓ (`worldRegimePacks.js`) |
| Wasm path optional for hot `on_bar` during long evo | Deferred — HonestOptimize js/interp; D1 no dual worker |
| Stamp `repro.world` on every champion | Schema versioned ✓ |
| Optional `POST /world/muse/context` if Lab/web needs server-built tapes | Deferred — D1 client builders suffice |

**DoD**

- [x] Champion that wins only on train scenario fails holdout scenario gate (honest NO-GO).
- [x] Field-N / trials session still deflate (no World special-case cheating).
- [x] Evo never ranks on finalEquity alone — Truth gates unchanged.

**Landed (2026-08-03):** Desktop `evolveUnderWorld` + regime packs (conflict/outbreak/fx), holdout gate, `repro.world` stamp, WorldSimPanel **Evolve under world**, selftest `worldRegimeEvo.selftest.js`, Playwright evo path. Wasm evo + `/world/muse/context` deferred to P3 / revisiting D1-C.

### P3 — Dual-surface truth (map + lab)

**Goal:** One scenario artifact opens in World *and* Strategy Studio / Terminal with identical digests.

| Work | Notes |
| --- | --- |
| Deep-link `mederos://world/scenario/{scenarioKey}` ↔ Studio tape binder | Mobile terminal session |
| Web parity via `WEB_SURFACE_PARITY_PLAN` ForecastHost + Muse sync | mederos-web |
| Shared “World Lab” panel: scrubber + chart + Truth + Brier curve | Product surface |
| Insight unlock path for world-calibration streaks | Constitution Insight — non-cashable |

**DoD**

- [ ] equityDigest + fillDigest match across World and Lab for the same repro blob.
- [ ] Published claims show reliability curve; no P&L leaderboard tile on World.
- [ ] Privacy: strategy source never uploaded to `/world/*`.

---

## Product / UX beats (Desktop World)

1. **Select shock(s)** on the map or feed (existing).
2. **Propagate** — existing Sim panel (intensity, n_runs, remediation, counterfactual).
3. **Brain awaken** — primary controls: **Light Muse** / **Evolve under world**.
   - Status row: `propagating…` → `ran` → `muse: GO|CAUTION|NO-GO` (evo adds holdout NO-GO chip).
4. **Scrub shared clock** — moving the contagion scrubber updates Muse aux “now”; optional live re-signal.
5. **Overlay legend** — “Jormungandr · Muse”: signal heat, forecast cone opacity = p, click node → claim + Brier if resolved.
6. **Open in Lab** — ships the `WorldContext` + bars + source binding into Terminal/Studio session (P3; P0 can copy scenarioKey only).
7. **History** — sim history entries show whether a Muse run was attached; re-apply restores both fan and last Muse overlay.

Tone: merciless honesty. If bridge skipped, Muse button disabled with the humanized skip reason — never a decorative fake brain glow.

---

## Non-goals / constitution constraints

- **No P&L as currency or leaderboard rank** on World or World-scenarios (SPEC §7–8, Constitution Art. III / IV).
- **No fake certainty:** unmapped observables, zero magnitude, unavailable CLI → skip; Muse must not fill with invented fans.
- **No strategy-source upload** to worldfeed / slim node for “cloud backtest”.
- **No custody / broker conflation** — World+Muse is an instrument for *belief quality*, not auto-trading.
- **No silent synth scrub envelopes** — Desktop already forbids peak-synthesized series; Muse overlays inherit that rule.
- **Not replacing fincog** — MuseScript does not become the Causal Graph; it *consumes* fans.
- **Not blocking feed** — Muse failures never stall `/world/feed` or aviation/shipping layers.

---

## Open decisions (choose explicitly)

### D1 — Where does the Muse brain execute for World?

| Option | Pros | Cons |
| --- | --- | --- |
| **A. Desktop/browser only** (reuse `museRuntimeClient`) | Matches Lab; no source upload; fastest P0; Constitution-aligned | Heavy evo strained on weak GPUs/CPUs; web parity later |
| **B. Python node shells Muse like `sim_bridge`** | Shared with headless jobs; one place for batch scenarios | Privacy/posture risk if source is sent; Graal/Haxe spawn cost; torch-free node discipline |
| **C. Dual: interactive client + optional headless worker with user-owned bundle** | Scales evo; keeps interactive privacy | Two pipes to maintain; auth/bundle complexity |

**Recommendation:** **A for P0–P1**; revisit **C** only when P2 evo walls the client. Do not start with B.

**Resolved (P0):** **A — Desktop/browser only.**

**P2 note:** Client evo remains on Desktop/browser (`evolveUnderWorld`). Dual worker (C) and Wasm HonestOptimize still deferred — P2 does not wall the client enough to justify a second pipe.

### D2 — Time alignment of market bars ↔ activation(t)

| Option | Pros | Cons |
| --- | --- | --- |
| **A. Timestep tape** (1 bar per sim step) | Perfect fan alignment; Wasm scrub trivial | Distorts real market microstructure; synthetic OHLCV honesty burden |
| **B. Calendar splice** (as-of join) | Real tape truth preserved; Lab familiarity | Need careful PIT join; sparse early fan samples |
| **C. Dual export** (both tapes, flag in `WorldContext`) | Empirically comparable; no premature lock | 2× surface; users may confuse |

**Recommendation:** ship **B as default** for P0 honesty; expose **A** behind `alignment: "timestep"` for scrub demos. Prefer **C** only if P1 research needs both.

### D3 — ForecastHost “world” kind vs adapter-only

| Option | Pros | Cons |
| --- | --- | --- |
| **A. Adapter-only** (enrich bars → existing kinds) | Zero engine churn; parity with Lab | Clouds are price-centric, not node-centric |
| **B. New `kind: "world"`** wrapping fincog fan quantiles as clouds | Map-native language; Brier shared with Causal Sim | New host + parity CI; risk of dual forecast ontologies |
| **C. Thin Haxe `WorldFanHost` in muse-script that only reshapes JSON** | Typed, testable, still not a second causal engine | Another `@:expose` bundle to sync (`sync-web-runtime.ps1`) |

**Recommendation:** **A for P0**; **C in P1** if map UX needs node-keyed clouds without claiming a new causal model. Avoid **B** until ontology is specified with muse_fincog Calibration.

### D4 — New dependency for World tape / paint?

| Need | Candidates | Pros / Cons |
| --- | --- | --- |
| Client tape join | **None** (pure JS like `jormungandrSimSeries.js`) vs lodash/date-fns | Zero-dep matches World stack; date-fns helps TZ edge cases rarely needed (sim `t` is days) |
| Map layers | **Existing deck.gl** vs new viz lib | Must reuse deck; no new map stack |
| Worker evo (P2) | **None** vs `comlink` + Worker | comlink nicer DX; adds dep — only if P2 chooses client-parallel evo |

**Recommendation:** no new deps through P1. If P2 picks client-parallel evo, present comlink vs raw Worker then.

---

## Implementation sketch (P2 landed on Desktop)

```
muse-script/
  JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md     ✓ P2 DoD
  examples/world/shock_gated_trend.ms            ✓
  examples/world/shock_gated_trend_evolve.ms     ✓ P2
  docs/WORLD_CONTEXT.md                          ✓ (+ P2 evo / holdout / repro.world)

mobile/src/world/
  worldContext.js                                ✓
  worldTapeBuilder.js                            ✓
  worldMarketTape.js                             ✓ SPY calendar + degrade badge
  worldCalibration.js                            ✓ claim Brier + precommit score
  worldRegimePacks.js                            ✓ conflict / outbreak / fx (+ disaster)
  worldMuseBridge.js                             ✓ run / forecast / evolveUnderWorld / repro.world
  jormungandrMuseOverlay.js                      ✓ signals + forecasts layers
  WorldSimPanel.jsx                              ✓ Light Muse + Evolve under world + Brier
  WorldView.jsx                                  ✓ muse-signals + muse-forecasts + evo

mobile/src/lab/
  honestLedger.js                                ✓ scenarioKey / worldRunId
  honestLeaderboard.js                           ✓ scenario field filter; cross-rank refused

kalshi-ai-advisor/python/worldfeed/
  routes.py                                      (POST /world/muse/context → P3 optional)
  WORLD_DATA_PLATFORM.md                         (one-paragraph cross-link)

muse_fincog/docs/WORLD_SIM_BRIDGE.md             (cross-link only — fans remain source of truth)
```

Sync path unchanged: `tools/sync-web-runtime.ps1` for engine bundles; World adapter code stays Desktop-owned until a Haxe promote is justified.

---

## Success metrics (product, not vanity)

1. **Time-to-wow:** cold Desktop → event → Muse overlay &lt; 30 s with mock bridge.
2. **Honesty rate:** 100% of Muse World runs either attach TruthReport or return `{ok:false}` with reason.
3. **Lookahead incidents:** 0 (selftests).
4. **Calibration loop:** ≥1 Brier-resolved claim path exercised end-to-end by P1 DoD.
5. **Cross-surface digests:** World ↔ Lab equality by P3.

---

## Appendix — MuseRuntime surface (current, for integrators)

`run`, `runPanel`, `emitWat`, `runWasm`, `proveDeterminism`, `evaluateTruthReport`, `trials*`, `optimize`/`evolve`, `buildReportCard`, `seedRobustnessSweep`, `ledgerEntryFromTruth`, `evaluateLeaderboardEntry`, `rankLeaderboard`, `forecastFields`, `estimatePbo`, `purgeEmbargoSplit`, `equityDigest`, `foundationDigest`, `debug`, `check`, `pluginKinds`, `checkWidget`, `runWidget`.

ForecastHostRuntime: `kinds()`, `forecast(kind, bars, opts)` — `regime` | `auction` | `lattice`.

Desktop World already: `toSimulatePayload`, `fetchWorldSimStatus`, `extractSimSeries`, `runAtSimTime`, history re-apply.

These are the bricks; WorldContext is the mortar.
