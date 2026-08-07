# Jormungandr → Business-Interest Management & World-Monitoring Dashboard

*Product + architecture plan. Written 2026-08-05. Home: muse-script (this plan). Body: `kalshi-ai-advisor/python/worldfeed` + Desktop `mobile/src/world/`. Cross-links: `JORMUNGANDR_GEOSPATIAL_CRE_PLAN.md`, `JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`, `JORMUNGANDR_MIROFISH_INSPIRATION.md`, `kalshi-ai-advisor/python/WORLD_DATA_PLATFORM.md` §11.*

**Status:** P3 shipped (Muse under interest scenarios — scenarioKey bind, Muse context chip, Open scenario from sim alerts). Soft, ambitious. Constitution: honest provenance; Brier/calibration ranks — **never P&L leaderboards**; exposure scores are situational, not money PnL; interest title is Muse **context**, never a score.

**Blueprints synthesis (2026-08-05):** Interest / Company signal sinks in MuseLab Blueprints
(`mobile/src/lab/blueprints/blueprintInterestSinks.js`) — Event-lane graphs that pin / alert /
open dossier / research without `long()`/`flat()`, with coverage-not-trading Truth. See
`FORGE_OVERHAUL_PLAN.md` “Interest / Company signal sinks” and Blueprints README.
Not a P1 alert-feed replacement — a Muse authoring path into the same book.

**Name collision (important):** `GET/POST /interests` on the advisor already stores a **string topic list** in `user_profile.db` (LLM/topic prefs). This plan’s **Business Interests** are first-class geo/CRE/market entities under `/world/interests`. Do not overload the topic string list.

---

## Executive summary

Jormungandr today is a **world situation shell** — MapLibre map, event feed, flights/shipping, contagion sim, Muse Light/Evolve, ops sheet, dual scrub, CRE/geo layers in flight. The product pivot is to make that shell *serve a book of interests*: holdings, watch targets, symbols, regions, counterparties — with the map and sim as sensors, not the homepage metaphor alone.

| Slice | Role in the dashboard |
| --- | --- |
| Map | Primary spatial context: interests + world layers + CRE triad |
| Interest portfolio | CRUD book of what the operator cares about |
| Alerts / monitoring | When feed, sim, or CRE touches an interest |
| Muse / Truth | Scenario drill under an interest (P3); Brier-not-P&L |

**Phased DoD spine:** P0 interest drawer on World (LA CRE triad + pin) → P1 alert feed → P2 multi-interest portfolio map → P3 Muse under interest scenarios.

---

## 1. Product thesis

### What a “business interest” is

A **Business Interest** is a durable, named object the operator wants the world stack to *watch for them* — not a one-shot map click.

| Kind | Examples | Why it belongs |
| --- | --- | --- |
| `cre_listing` | A LoopNet/fixture listing in Lafayette or a merge_id dossier | Crown jewel: site selection + asset watch |
| `asset` | A building / parcel / portfolio property (stable even if listing id churns) | Holdings that outlive listing scrapes |
| `symbol` | Equity / FX / commodity / Kalshi market key | Markets as interests without inventing P&L ranks |
| `region` | Metro (Lafayette/NOLA/BR), parish, ISO admin, corridor bbox | Geo exposure without a single pin |
| `counterparty` | Broker, tenant, supplier, carrier, port | Relational watch (soft links + optional geo) |

Each interest may carry:

- **Geo** — point, polygon, or region key (nullable for pure symbols).
- **Links** — `cre_id` / `merge_id`, `scenarioKey`, Lab deep-link, watchlist membership.
- **Intent** — hold | watch | research | rival (label only; not a trading instruction).
- **Provenance** — who pinned it, when, source (manual | cre_seed | import).

### vs raw world monitoring

| World monitoring (today) | Business-interest management (target) |
| --- | --- |
| Global feed & choropleth for *everything* | Same sensors, **filtered / scored** to the book |
| Nation / event dossiers | Interest dossier = event + CRE + sim facets for *that* entity |
| Sim scrub explores “what if anywhere” | P3: sim / Muse framed as **interest scenario** |
| Ops sheet = platform health | Alerts = *your* exposures firing |
| CRE layer = market inventory | CRE listings become **pinnable interests** |

Raw World remains the substrate (WORLD_DATA_PLATFORM contract unchanged). Interests are a **lens + persistence layer** over it — Plague-Inc map energy, asset-manager focus.

**Ambition (soft):** Mederos Desktop’s default World path evolves from “look at the planet” to “manage exposure to a living world” — still honest about uncertainty, still keyed by calibration not cash.

---

## 2. IA / surfaces

### Desktop shell (target layout)

Evolve today’s **Map | Split | Muse** triad (`worldLayout.js`, MiroFish inspiration remapped — already shipped) into a four-pane *product* information architecture. Modes stay chrome-cheap; panels compose.

```
┌──────────────────────────────────────────────────────────────────────────┐
│  World · Business Interests                          [Map|Split|Muse]    │
├────────────────┬───────────────────────────────┬─────────────────────────┤
│                │                               │  Alerts / monitoring    │
│  Interest      │         MAP (MapLibre)         │  · proximity hits        │
│  portfolio     │   interests · CRE · pop ·     │  · CRE status deltas    │
│  · pin / unpin │   flights · vessels · events  │  · sim activation       │
│  · kind filter │                               │  · confidence chips     │
│  · LA triad    │                               ├─────────────────────────┤
│    quick seeds │   detail / dossier drawer →   │  Muse / Truth (P3+)     │
│                │   (P0 interest drawer here)   │  · scenarioKey scoped   │
│                │                               │  · Brier / reliability  │
└────────────────┴───────────────────────────────┴─────────────────────────┘
```

| Surface | Owns | Primary actions |
| --- | --- | --- |
| **Map** | Spatial truth | Select interest; cluster pins; layer toggles (CRE, Kontur, roads, feed) |
| **Interest portfolio** | The book | List / filter / pin from CRE or region; edit kind & links |
| **Alerts / monitoring** | Time-ordered exposure events | Ack, open interest, deep-link Lab / event / CRE dossier |
| **Muse / Truth** | Calibrated scenario work | Run Light/Evolve under interest `scenarioKey`; never P&L rank |

### How Map | Split | Muse evolves

| Mode today | Dashboard reading |
| --- | --- |
| **Map** | Map + thin bottom/side interest drawer (P0). Portfolio list can collapse. |
| **Split** | Map \| (Alerts + Interest detail + optional Casual Sim fans). Default “operator” mode. |
| **Muse** | Workbench (Light / Evolve / Truth / Brier) with **interest context chip** once P3 lands — aux columns / `WorldContext` already proven; scenario scoped to interest. |

**Do not** invent a parallel route tree in v1 — stay inside `mobile/src/world/` and extend `WorldView` / dossier chrome / ops sheet patterns. Ops sheet remains **platform** health; interests get their own drawer/feed.

Optional IA canvas companion (Cursor): `Business Interest Dashboard IA` — layout sketch only.

---

## 3. Data model

### Interest entity

```ts
type InterestKind =
  | "cre_listing"
  | "asset"
  | "symbol"
  | "region"
  | "counterparty";

type InterestGeo =
  | { type: "point"; lat: number; lng: number; label?: string }
  | { type: "bbox"; west: number; south: number; east: number; north: number }
  | { type: "region_key"; key: string }  // e.g. "metro:lafayette_la", "US-LA", ISO-3166-2
  | null;

type BusinessInterest = {
  id: string;                     // ulid / sha1 stable
  owner_id: string;               // "local" until multi-tenant lock
  kind: InterestKind;
  title: string;
  notes?: string;
  intent?: "hold" | "watch" | "research" | "rival";
  geo: InterestGeo;
  links: {
    cre_ids?: string[];           // /world/cre/{id}
    merge_ids?: string[];
    scenario_keys?: string[];     // Muse / Lab / simulate
    symbols?: string[];           // markets / tickers
    counterparty_ids?: string[];
    watchlist_ids?: string[];
    lab_deeplink?: string;
  };
  tags?: string[];
  created_at: number;             // epoch s
  updated_at: number;
  provenance: {
    source: "manual" | "cre_seed" | "import" | "alert_promote";
    created_by?: string;
    pipeline?: string;
  };
  // Denormalized convenience for map (optional cache)
  map_pin?: { lat: number; lng: number; color_hint?: string } | null;
};
```

### Alert entity

```ts
type InterestAlert = {
  id: string;
  interest_id: string;
  ts: number;
  trigger:
    | "world_event_proximity"
    | "world_event_region"
    | "sim_shock_activation"
    | "cre_status_change"
    | "cre_price_change"
    | "feed_keyword"
    | "manual";
  severity: number;               // 0–1 mirror WorldEvent severity where applicable
  confidence: number;             // 0–1 honest; lower when geo fuzzy / estimated
  summary: string;
  refs: {
    event_ids?: string[];
    cre_ids?: string[];
    sim_run_id?: string;
    scenario_key?: string;
  };
  acknowledged_at?: number | null;
  provenance: { pipeline: string; rule_version: string };
};
```

### Exposure score (non-P&L)

Exposure is a **situational** aggregate — *how much the living world is currently pressing on this interest* — not unrealized gain/loss.

```ts
type InterestExposure = {
  interest_id: string;
  as_of: number;
  score: number;                  // 0–1 composite
  components: {
    event_proximity: number;      // inverse distance × event severity (clamped)
    event_severity_max: number;
    sim_activation: number;       // max |activation| / exceedFrac on linked scenarioKey
    cre_churn: number;            // status/price delta magnitude (normalized, labeled)
    confidence: number;           // min provenance confidence across inputs
  };
  explanation: string[];          // short honest bullets for UI
  quality: "observed" | "estimated" | "partial";
};
```

**Hard rules:**

- Never surface exposure as “$ at risk” or portfolio P&L.
- Always show `quality` + component breakdown (constitution / CRE plan honesty).
- Missing sim or CRE → component `0` + status reason, not invented heat.

### Disambiguation vs topic interests

| Store | Shape | API |
| --- | --- | --- |
| Topic prefs (existing) | `string[]` free text | `/interests` via `UserProfileDB` |
| Business Interests (this plan) | rich entities + geo + links | `/world/interests` |

UI copy: **Topics** vs **Business Interests** — never share a noun in nav without a qualifier.

---

## 4. Alerting

### When does an alert fire?

| Trigger | Condition (sketch) | Inputs |
| --- | --- | --- |
| World event proximity | Event has lat/lng; interest has point/bbox; haversine or bbox contain within radius \(r\) (default metro-scale, e.g. 25–80 km configurable) | `/world/feed`, interest.geo |
| World event region | Event nation/subdivision intersects interest `region_key` | geometry / alpha-2 / ISO-3166-2 |
| Sim shock | Linked `scenarioKey` run shows exceedFrac or node |activation| above threshold | `/world/simulate`, MuseEvents `world.shock` |
| CRE change | Linked `cre_id` status/price/cap_rate changes vs last_seen | `/world/cre`, scheduler digest |
| Keyword (optional P1.5) | Title/summary match interest tags | feed digester |

### Pipeline

```
worldfeed digestion / CRE refresh / simulate persist
        │
        ▼
interest_matcher.py (new)  — bbox + region + link joins
        │
        ▼
interest_alerts table  (+ optional MuseEvents pump: world.interest_alert)
        │
        ▼
GET /world/interests/alerts?since=   ← Desktop alert rail
```

Reuse:

- Severity decay / corroboration from WORLD_DATA_PLATFORM §4.
- Dual scrub / feed pins patterns for time alignment (MiroFish B — shipped).
- Dual-lane honesty: empty alert rail is OK; never invent proximity.

### Notification channels (open — see §7)

P0–P1: **in-app alert rail only**. Push/email/desktop toast deferred to lock.

---

## 5. Phased roadmap (P0–P3) with DoD

### P0 — Interest drawer on World (LA CRE triad + pin) ✅

**Goal:** Prove the lens without new notification infra.

| Deliverable | DoD | Status |
| --- | --- | --- |
| Schema + SQLite table(s) for Business Interests | Rows survive restart; `owner_id=local` | ✅ `business_interests` (+ empty `interest_alerts`) |
| `GET/POST/PATCH/DELETE /world/interests` | CRUD works for kinds `cre_listing` + `region` | ✅ + pin CRE + seed LA triad |
| Seed helpers | One-click pin for Lafayette / New Orleans / Baton Rouge metro regions + pin from CRE dossier/marker | ✅ |
| Desktop drawer | Collapsible interest list + “Pin interest” on CRE; map pins for pinned geos | ✅ `WorldInterestDrawer` |
| Honesty chrome | Provenance chip; no exposure scores yet (or stub `partial`) | ✅ exposure stub `quality=partial` |

**Depends:** CRE P0 fixtures + legend (see Geospatial CRE plan) — triad markets already locked.

**Effort:** S–M (mostly chrome + thin store).
### P1 — Alert feed ✅

| Deliverable | DoD | Status |
| --- | --- | --- |
| Matcher: event proximity + region intersect | Alert row when quake/outbreak/etc. hits pinned metro | ✅ `interest_matcher.run_match_pass` |
| Matcher: CRE status/price delta | Alert when fixture/listing row churns for pinned cre_id | ✅ snapshots + `cre_*_change` |
| `GET /world/interests/alerts` | Cursor/`since`; ack endpoint | ✅ + `POST …/match` |
| Desktop alert rail in Split | Click → focus interest + open event/CRE dossier | ✅ `WorldAlertRail` |
| MuseEvents (optional) | `world.interest_alert` catalog reserve (host, non-det) — document only if not wired | ✅ reserved in `jormungandrMuseEvents.js` (not pumped) |

**Effort:** M.

### P2 — Multi-interest portfolio map ✅

| Deliverable | DoD | Status |
| --- | --- | --- |
| Portfolio filters | kind, intent, tag; multi-select focus | ✅ drawer chips + `intent=` query; focus Set |
| Map clustering / emphasis | Selected interests lit; others dim | ✅ `interestPortfolioMap.js` (not proximity rename overload) |
| `GET /world/interests/{id}/exposure` | Components + explanation; quality labeled | ✅ `component_labels` + weights + honesty note |
| Symbol + counterparty kinds | Minimal: symbol without geo; optional region hop | ✅ helpers + import + drawer quick-add |
| Import | CSV/JSON of interests (manual provenance) | ✅ `POST /world/interests/import` source=`import` |

**Effort:** M–L.

### P3 — Muse under interest scenarios ✅

| Deliverable | DoD | Status |
| --- | --- | --- |
| Interest ↔ `scenarioKey` binding | Pinning a scenario from Causal Sim / Lab writes `links.scenario_keys` | ✅ `POST /world/interests/{id}/scenarios` + Desktop “Pin scenario → interest” |
| Muse / Truth context chip | Light & Evolve runs carry interest id in `WorldContext` / Lab session digest | ✅ `worldContext.interest` (role=context; excluded from scenarioKey hash) + Lab artifact + chip |
| Alert → Muse | “Open scenario” from sim_activation alerts | ✅ `sim_shock_activation` matcher + Alert rail Open scenario → history / Lab |
| Live world.* (per MuseScript integration plan) | Prefer tape/`EventLog` path; truth-mode stays deterministic | ✅ Reuses existing `worldMuseBridge` tape path + `proveDeterminism`; no parallel Muse rebuild |
| Constitution check | Leaderboards / fitness remain Brier/calibration — interest title is context, not score | ✅ Chip copy + bind note + exposure explanations |

**Effort:** L (engine seams already planned in `JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`).

**Dashboard roadmap:** P0–P3 complete for the Business-Interest Management & World-Monitoring Dashboard spine.

### Suggested calendar (soft)

| Week band | Ship |
| --- | --- |
| W0–W1 | P0 alongside CRE fixtures triad |
| W2–W3 | P1 alerts (feed + CRE churn) |
| W4–W5 | P2 portfolio map + exposure API |
| W6+ | P3 Muse binding as MuseScript world.* matures |

---

## 6. API sketches

Mounted with existing worldfeed routes (`register_worldfeed_routes` on main + mederos_node).

### CRUD

```http
GET    /world/interests?owner_id=local&kind=&tag=&bbox=
POST   /world/interests
GET    /world/interests/{id}
PATCH  /world/interests/{id}
DELETE /world/interests/{id}
```

```json
// POST body
{
  "kind": "cre_listing",
  "title": "Lafayette industrial — fixture #12",
  "intent": "watch",
  "geo": { "type": "point", "lat": 30.22, "lng": -92.02 },
  "links": { "cre_ids": ["cre_fixture_lafayette_12"] },
  "provenance": { "source": "cre_seed" }
}
```

```json
// GET list response
{
  "interests": [ /* BusinessInterest */ ],
  "count": 3,
  "generated_at": "2026-08-05T12:00:00Z",
  "status": { "owner_id": "local", "quality": "observed" }
}
```

### Exposure & alerts

```http
GET  /world/interests/{id}/exposure
GET  /world/interests/alerts?owner_id=local&since=&interest_id=&limit=
POST /world/interests/alerts/{alert_id}/ack
```

```json
// exposure response
{
  "interest_id": "…",
  "as_of": 1722860000,
  "score": 0.42,
  "components": {
    "event_proximity": 0.55,
    "event_severity_max": 0.7,
    "sim_activation": 0.2,
    "cre_churn": 0.0,
    "confidence": 0.6
  },
  "explanation": [
    "Active disaster event within 40 km (severity 0.7).",
    "No CRE status change since last_seen.",
    "Sim fan exceedFrac 0.12 on scenario lafayette_corridor (below alert threshold)."
  ],
  "quality": "partial"
}
```

### Status honesty

`GET /world/status` → add `jormungandr.interests`: `{ count, alert_unread, matcher_last_ok, storage }`.

### Non-goals for these routes

- No trading/order endpoints.
- No scrape of private CRM books.
- No silent merge with topic `/interests` strings.

---

## 7. Open decisions (need user lock)

### D1 — Where do Business Interests live?

| Option | Pros | Cons |
| --- | --- | --- |
| **A. worldfeed SQLite** (`data/worldfeed.db` new tables) | Same process as feed/CRE/sim; bbox joins easy; status block natural | Mixes user book with global accreted world data; backup semantics blur |
| **B. accounts / user_profile DB** (extend beyond string list) | Clear ownership; multi-user path later; topic interests sibling | Cross-DB joins for proximity; mederos_node must dual-open; richer schema than JSON blob |
| **C. Hybrid** — worldfeed stores geo indexes + alert materializations; profile stores ownership metadata | Clean split of “world facts” vs “my book” | Two writes per pin; sync bugs |

**Recommendation:** **A for P0–P1** (velocity beside CRE), with `owner_id` column from day one so **B/C migration** is possible. Revisit at first true multi-user.

### D2 — Notification channel

| Option | Pros | Cons |
| --- | --- | --- |
| **A. In-app alert rail only** | Honest, offline-friendly, no spam | Missed if Desktop closed |
| **B. Desktop OS notifications** | Operator interrupt | Permission friction; noise |
| **C. Email / webhook** | Multi-device | Creds, privacy, delay |
| **D. MuseEvents bus only** | Great for strategies | Easy to miss in UI |

**Recommendation:** **A through P1**; reserve MuseEvents envelope; decide B/C after alert precision is proven.

### D3 — Multi-tenant

| Option | Pros | Cons |
| --- | --- | --- |
| **A. Single-user `owner_id=local`** | Matches Desktop today | Blocks shared desk |
| **B. Soft multi-user** (string owner_id, no auth hard wall) | Unblocks demos | Not real security |
| **C. Auth-backed tenants** | Product-real | Depends on auth roadmap |

**Recommendation:** **A + column for B**; no auth wall until product asks.

### D4 — Default proximity radius / scoring weights

| Option | Pros | Cons |
| --- | --- | --- |
| **A. Fixed metro defaults** (e.g. 50 km; equal component weights) | Ship fast | Wrong for rural assets vs CBD |
| **B. Per-interest overrides** | Correct for CRE | UI complexity P0 |
| **C. Adaptive by kind** | Sensible priors | Opaque unless explained |

**Recommendation:** **A + C hybrid** — kind priors in matcher; per-interest override fields optional from P2.

### D5 — Relationship to topic `/interests`

| Option | Pros | Cons |
| --- | --- | --- |
| **A. Keep forever separate** | No collision | Two “interest” concepts |
| **B. Rename topic API to `/topics`** | Clears noun | Churn for existing clients |
| **C. Nest topics under profile only in UI** | Soft rename | API debt remains |

**Recommendation:** **A + UI rename to Topics**; schedule **B** when touching profile settings next.

---

## 8. Seams to extend (file touch map)

| Concern | Extend |
| --- | --- |
| Store | `worldfeed/store.py` — `business_interests`, `interest_alerts` tables |
| Matcher / jobs | `worldfeed/interest_matcher.py` + scheduler job `interest_match_pass` |
| HTTP | `worldfeed/routes.py` — `/world/interests*` |
| Status | `jormungandr.interests` on `/world/status` |
| Desktop | `WorldView.jsx` drawer; `worldInterestsClient.js`; pins layer beside `jormungandrCre.js` |
| Layout | `worldLayout.js` — Split hosts alert rail; Muse chip later |
| Muse / Lab | `worldLabSession.js` / `WorldContext` — interest id + scenarioKey (P3) |
| Events bus | `MuseEvents` catalog reserve `world.interest_alert` (optional P1) |
| Contracts | This plan + WORLD_DATA_PLATFORM §11 pointer |

---

## 9. Tiny stubs (optional — not required to accept this plan)

1. Fixture 3 region interests (LA triad) written by a one-shot seed script.
2. Drawer list component reading `GET /world/interests` with empty-friendly chrome.
3. “Pin as interest” button on CRE dossier writing `POST /world/interests`.

No full dashboard shell rewrite until P0 DoD lands.

---

## 10. Cross-links & constitution

- CRE triad + hybrid ingest: `JORMUNGANDR_GEOSPATIAL_CRE_PLAN.md`
- Muse / Frame / world.* : `JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`
- Layout ancestry: `JORMUNGANDR_MIROFISH_INSPIRATION.md`
- Platform contract: `WORLD_DATA_PLATFORM.md` §11 (interests slice pointer)
- **Never:** money leaderboards, fake certainty, silent scrape escalation for “better alerts”

---

## Open decisions checklist (locked 2026-08-05)

- [x] D1 storage: **A worldfeed** + `owner_id` column
- [x] D2 notifications: **A in-app** through P1
- [x] D3 tenancy: **A local + owner_id column**
- [x] D4 radius/weights: **A+C** metro defaults + kind priors (`interest_matcher.py`)
- [x] D5 topic rename schedule: **A now** (keep `/user/interests`; UI = Topics), **B later**

*End of plan.*
