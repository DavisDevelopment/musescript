# MuseScript event bus (`MuseEvents`)

Schema: `musescript.events/1`

Out-of-band pub/sub for Lab, broker, watchlist, UI, meta, world, and lifecycle —
so scripts and hosts can react without polling. **Not** a replacement for
strategy-language `@on(bar)` / `@on(tick)` / `@on(stream)` (those stay the
bar-synced trading path on MuseInterp / emitters).

Source: `musescript/runtime/MuseEvents.hx`. Facades on `MuseRuntime`.

---

## Register / emit (JS host)

```js
import { MuseRuntime } from "./museRuntimeClient.js";
// or window.MuseEvents after build-runtime.hxml

const off = MuseRuntime.on("order.status", (e) => {
  console.log(e.status, e.symbol);
});

MuseRuntime.once("lifecycle.stop", (e) => { /* … */ });

MuseRuntime.pumpHostEvent({
  type: "order.suggested",
  summary: { n: 1, headline: "long SPY" },
  runId: "r1",
});

// or
MuseRuntime.pumpHostEvent("watchlist.ping", { symbol: "SPY", kind: "alert" });

off(); // or MuseRuntime.off("order.status", handler)
MuseRuntime.eventsClear(); // session reset
```

Wildcards: `order.*`, `*`.

---

## Event catalog (summary)

| Type | Family | Class | Det? | Payload (sketch) |
|------|--------|-------|------|------------------|
| `market.bar` | market | det | yes | barIndex, OHLCV, symbol? |
| `market.tf_roll` | market | det | yes | fromTf, toTf, barIndex |
| `order.submit` | order | det | yes | orderId?, side, qty?, price? |
| `order.fill` | order | det | yes | side, qty, price, barIndex?, pnl? |
| `order.partial` | order | det | yes | qty, filledQty, price |
| `order.cancel` | order | det | yes | orderId?, reason? |
| `order.reject` | order | host | no* | reason |
| `order.status` | order | host | no | status, prevStatus? |
| `order.suggested` | order | host | no | summary, runId? (human-gated) |
| `watchlist.add` / `.remove` / `.ping` | watchlist | host | no | symbol, … |
| `interest.pin` / `.alert` / `.dossier` / `.research` | interest | host | no | symbol, intent, … (Company / Business Interests — not orders) |
| `ui.click` / `.selection` / `.focus` / `.command` | ui | host | no | target / panel / command |
| `meta.reload` | meta | host | no | sourceId? |
| `meta.macro_expand` | meta | det | yes | macro, resultDigest? |
| `meta.diagnostics` | meta | det | yes | diagnostics[] (from `check`) |
| `meta.strategy_swap` | meta | host | no | from?, to? |
| `world.shock` / `.scrub` / `.muse_light` / `.muse_evolve` | world | host | no† | scenarioKey?, t?, … |
| `lifecycle.start` / `.stop` / `.error` / `.dispose` | lifecycle | det | yes | runId?, backend?, error? |

\* Recorded rejects on an `EventLog` tape may be replayed as det only when the tapis the source of truth — default host rejects stay quarantined.  
† World is an optional thin channel (no strategy upload). Treat as host unless a
recorded WorldContext event log is replayed under truth.

Full notes / payload strings: `MuseRuntime.eventsCatalog()`.

---

## Determinism quarantine

| Mode | Behavior |
|------|----------|
| `live` (default) | All event classes emit. |
| `truth` | Only `deterministic: true` catalog types emit. Host/UI/watchlist/world pumps return `{ ok:false, reason:… }`. |

```js
MuseRuntime.eventsSetMode("truth");   // before proveDeterminism / evolve fitness
MuseRuntime.eventsSetMode("live");    // Lab UI session
```

**Rules**

1. Listeners on truth/evolve/replay paths must not call `Date.now`, `Math.random`,
   network, or host UI — only DetRng / tape-derived inputs.
2. Prefer strategy `@on(bar)` for trading decisions; use the bus for Lab overlays,
   notifications, and host glue.
3. `lifecycle.*` and `meta.diagnostics` are det envelopes; clear listeners before
   bit-identical proofs if a listener mutates shared state.
4. **Constitution:** no event type is a ranking channel. `order.suggested` /
   world muse results never promote P&L vanity onto Honest Leaderboard.

Pass `emitLifecycle: false` on `run` / `emitDiagnostics: false` on `check` to silence
runtime-originated bus traffic.

---

## Backpressure

- History ring capped (default 64; `setMaxDepth` clamps ≥ 8).
- Drop-oldest; `MuseEvents.droppedCount()` counts overflows.
- Listener exceptions are swallowed per handler so one bad subscriber cannot
  take down the bus.
- Nested emit is allowed; deep storms increment the drop counter.

---

## Relation to `@on(stream)`

Language hooks:

```ms
@on(orders) { log("status=" + status); }
```

Host bus:

```js
MuseRuntime.on("order.status", (e) => { /* Lab */ });
```

Lab may later bridge bus → `MuseInterp.dispatchEvents("orders", …)`. Until then,
`.ms` examples document the stream names hosts should aim at; reactive Lab code
uses `MuseRuntime.on` / `pumpHostEvent`.

---

## Host wiring status

| Path | Status |
|------|--------|
| `MuseRuntime.run` → `lifecycle.start/stop/error` | **Live** (opt-out `emitLifecycle:false`) |
| `MuseRuntime.check` → `meta.diagnostics` | **Live** (opt-out `emitDiagnostics:false`) |
| Swarm `order.suggested` via `pumpHostEvent` | **Live** (mobile `createLiveScheduler`) |
| Broker fill/reject/status | **Live** (mobile `orderMuseEvents.js` ← TradeSheet + DeployBookSheet) |
| Watchlist add/remove/ping | **Live** (mobile `watchlistMuseEvents.js` ← SymbolPicker + signalAlerts) |
| Interest pin/alert/dossier/research | **Live** (mobile `interestMuseEvents.js` ← Blueprints Interest sinks) |
| UI click/selection/focus/command | **Live** (mobile `uiMuseEvents.js` ← Lab/Studio/Charts; selection throttled) |
| World shock/scrub/muse_* | **Live** (mobile `jormungandrMuseEvents.js` ← Desktop World) |

### Broker family (Kestrel / DeployBook)

| Host path | Events | Payload (small) |
|-----------|--------|-----------------|
| TradeSheet / DeployBook approve ok | `order.submit` → `order.status(submitted)` → `order.fill` → `order.status(filled)` | symbol, side, usd/qty/price?, orderId, dryRun?, runId? |
| TradeSheet / DeployBook approve fail | `order.reject` → `order.status(rejected)` | symbol, reason, runId? |
| `order.partial` / `order.cancel` | Helpers ready | No live cancel/partial broker path yet |

Never scores, ranks, or P&L vanity on the bus.

Selftest: `node src/lab/orderMuseEvents.selftest.js`

### Watchlist family

| Host path | Events | Payload |
|-----------|--------|---------|
| SymbolPicker add/remove (Lab/Studio/Swarm) | `watchlist.add` / `.remove` | symbol, listId (dataset) |
| `fireSignalAlert` (cockpit signals) | `watchlist.ping` | kind, message |

Selftest: `node src/lab/watchlistMuseEvents.selftest.js`

### Interest / Company family (Blueprints synthesis)

| Host path | Events | Payload |
|-----------|--------|---------|
| Blueprints Interest Run · pin_interest | `interest.pin` (+ Business Interests API when live) | symbol, creId?, intent, kind |
| Blueprints Interest Run · watch_alert | `interest.alert` (+ watchlist.ping) | symbol, message, trigger |
| Blueprints Interest Run · open_dossier | `interest.dossier` (+ `openCompany`) | symbol, panel, edgar? |
| Blueprints Interest Run · research_intent | `interest.research` | symbol, intent=research, note? |

Honesty: not trading orders; not OHLCV Prove. Coverage latch for Marketplace `blueprint_interest`.

Selftest: `node src/lab/interestMuseEvents.selftest.js` · `node src/lab/blueprints/blueprintInterestSinks.selftest.js`

### UI family (Lab / terminal only — not World)

| Host path | Events | Notes |
|-----------|--------|-------|
| StrategyLab symbol focus | `ui.selection` + `ui.focus` | throttled ~150ms |
| Lab ignite / Studio run | `ui.command` + `ui.click` | `lab.ignite` / `studio.run` |
| Charts widget palette | `ui.command` + `ui.click` + `ui.focus` | `charts.widget_palette` |

Selftest: `node src/lab/uiMuseEvents.selftest.js`

---

## World family (Jormungandr host)

Desktop World pumps via `src/world/jormungandrMuseEvents.js` (never strategy source):

| UI action | Event | Payload (small) |
|-----------|-------|-----------------|
| Simulate finishes (`status === "ran"`) | `world.shock` | `scenarioKey`, `eventIds`, `mag`/`dir`/`region`, `runId?` |
| Scrubber T drag (throttle ~150ms) | `world.scrub` | `t`, `step?`, `runId?`, `scenarioKey?` |
| Light Muse completes | `world.muse_light` | `scenarioKey`, `verdict?`, `reason?`, `ok` |
| Evolve-under-world completes | `world.muse_evolve` | `scenarioKey`, `holdoutScenarioKey?`, `found?`, `disposition?`, `reproWorld?` summary |

```js
import { MuseRuntime } from "./museRuntimeClient.js";

MuseRuntime.on("world.shock", (e) => {
  console.log("shock", e.scenarioKey, e.eventIds);
});
MuseRuntime.on("world.scrub", (e) => {
  console.log("scrub T=", e.t, "step", e.step);
});
MuseRuntime.on("world.muse_*", (e) => {
  // light / evolve results — Truth / holdout only; no .ms source on the bus
  console.log(e.type, e.scenarioKey, e.verdict || e.disposition);
});
```

Selftest: `node src/world/jormungandrMuseEvents.selftest.js` (mocked pump).

---

## Examples

- `examples/events/listen_orders.ms`
- `examples/events/listen_watchlist.ms`
- `examples/events/listen_ui_ping.ms`

See also: `docs/WORLD_CONTEXT.md`, `docs/PLUGIN_KINDS.md`, `JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`.
