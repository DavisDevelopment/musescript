# Jormungandr Geospatial + CRE Layers Plan

*Feasibility + architecture for four Mederos Desktop World layers. Written 2026-08-05. Home: muse-script (this plan). Body: `kalshi-ai-advisor/python/worldfeed` + Desktop `mobile/src/world`. Cross-links: `WORLD_DATA_PLATFORM.md`, `JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`, constitution stance: honest provenance, no fake certainty; Brier/not P&L for forecast ranks — **CRE is a commercial data layer, not a P&L leaderboard**.*

**Status:** plan only. No large scrapers implemented. Tiny validation spikes OK later; none required to accept this doc.

**Crown jewel (user rank):** commercial real-estate listings (multi-source ingest). Ship-order note: roads/population are often cheaper “map looks rich” wins while CRE scrape is **L**.

---

## Executive summary

| Layer | Top recommendation (default) | Effort | “Wow / week” vs “product depth” |
| --- | --- | --- | --- |
| 1. Roads | **Style emphasize** OpenFreeMap/OpenMapTiles highway classes first; optional **analytic** arterial GeoJSON later for CRE catchment / corridors | **S** → **M** | High wow, low risk |
| 2. Traffic density | **Defer paid live APIs**; optional sparse historical or OSM-derived “activity estimate” only with honest labels | **M–L** | Expensive / fragile / low integrity unless paid |
| 3. Population density | **Kontur H3 (HDX, CC BY)** tiled/rasterized for world + metro zoom; census as US refinement | **S–M** | High wow, clean provenance |
| 4. CRE listings | **Hybrid**: official/partner APIs where available + **narrow polite scrape** of public listing pages in **allowlisted metros**; schema + `GET /world/cre` + markers/dossier before scale | **L** (schema **S**, multi-source **L**) | Crown jewel depth |

**Biggest CRE lock needed from you before heavy build:**
1. **Ingest posture:** official APIs / licensed feeds vs scrape-only vs **hybrid** (recommended).
2. **Market scope v1:** which geographies first — recommendation below is **US metros** (LoopNet/Crexi gravity) before CREA/Canada or global portals.
3. **Legal comfort:** do you want counsel / ToS review gate before any LoopNet/Crexi-class scraper ships beyond a robots-checked spike?

**Grounded inventory (no CRE scrapers today):**
- World map: MapLibre + deck.gl (`mobile/src/world/`); basemap `WORLD_MAP_STYLE_URL = tiles.openfreemap.org/styles/dark` (OpenMapTiles schema — **style roads already present**).
- Overlays today: event choropleth, flights/airports, vessels/sea-lanes, Muse overlays — legend pattern in `WorldView.jsx`.
- worldfeed: write-through `fetch_through`, polite `scraper.py` (robots + 5 s/domain), scheduler swarm, digesters, outlets — **news/geo/aviation/shipping**, not CRE.
- `rg` across kalshi python: **no LoopNet / Crexi / CoStar / CRE listing adapters**. Closest reuse is `polite_get`, `geo_cache` / `GoogleMapsClient`, event `sources`+`provenance` contract, and snapshot tables (`flight_snapshot`, `vessels`, `sea_lanes`).

---

## Shared architecture (all four layers)

Fit the existing Jormungandr body/UI seam — do not invent a parallel stack.

```
external sources (tiles | dumps | APIs | allowlisted public pages)
        │  every network fetch → store.fetch_through()  (write-through)
        ▼
WorldFeedStore (SQLite)  +  job_ledger  +  raw_fetches
        │
scheduler.py jobs (interval + graceful skip when key/license absent)
        │
routes.py  GET /world/{roads|traffic|pop|cre}…   (+ status honesty fields)
        ▲
Desktop: world*Client.js → deck.gl / MapLibre style layers → legend toggles
```

**Non-negotiables (constitution + platform):**
- Provenance on every feature: `{ source, url?, scraped_at|fetched_at, pipeline, license_hint?, confidence? }`.
- No fake certainty: estimated congestion / inferred cap rates labeled `quality: estimated|scraped|official`.
- Keyless / license-missing → empty arrays + status reason (same honesty pattern as AIS key-absent).
- CRE never drives a money leaderboard; optional future Muse hooks stay context columns / spatial features only.

**UI patterns already proven:**
- Static GeoJSON seed: `/world/sea-lanes` → `jormungandrCorridors.js`.
- Live snapshot: `/world/flights`, `/world/vessels` → Scatterplot/Arc layers + legend.
- Choropleth: nation + subdivision GeoJsonLayer (`jormungandrSubdivisions.js`).
- Geocode assist: `GoogleMapsClient` + `geo_cache` (CRE address → lat/lng).

---

## 1. Road visualization

### Distinction (critical)

| Concept | What it is | What it is **not** |
| --- | --- | --- |
| **Style roads** | Vector-tile layers already in OpenFreeMap dark style (OpenMapTiles `transportation` / highway class paints). Cosmetic emphasis via `setPaintProperty` / filter by class at zoom. | Analytic graph for routing, AADT, or CRE catchment |
| **Analytic road network layer** | Explicit GeoJSON/MVT of selected highways/arterials with stable IDs, class, maybe length — queryable for overlays, buffers, “near arterial” flags on CRE | Replacing the basemap |

Today `applyPlagueTint` only retints ocean/background; road layers exist but are not productized as a World legend toggle.

### Options (you choose)

| Option | Pros | Cons | Fit |
| --- | --- | --- | --- |
| **A. Style emphasize** (paint/filter OpenMapTiles road layers; legend “Roads”) | Zero new deps; S effort; instant rich map; works offline only if tiles cached | Not queryable; class schema is style-convention not contractual; hard to attach CRE attributes | **Best Phase 0** |
| **B. Vendored arterial GeoJSON** (Geofabrik extract → filter motorway/trunk/primary → simplify → seed like `sea_lanes`) | Queryable; offline; parallels shipping static path; provenance clear (© OSM / ODbL) | Build/update pipeline; planet=huge → metro extracts; simplification tradeoffs | Best for CRE adjacency later |
| **C. Client Overpass / bbox pull** | Always fresh; no large binaries in repo | Rate limits; not polite at zoom pan scale; fragile for Desktop product | Avoid as primary |
| **D. Self-hosted MVT roads** (Tilemaker/Planetiler subset) | Scalable analytics tiles | Ops L; overlaps OpenFreeMap you already use | Only if analytic demand is proven |
| **E. Paid road network (HERE/TomTom SDK)** | Quality / traffic fusion path | Cost; key; ToS; unnecessary for viz alone | Skip unless traffic also locked paid |

### Fit with MapLibre / worldfeed / scheduler
- **Phase 0:** Desktop-only — style tweaks in `worldMapStyle.js` / `WorldView` map-on-load; no worldfeed.
- **Phase 1 analytic:** worldfeed table `road_segments` or static file under `data/roads/` + `GET /world/roads?bbox=&class=` (mirror `sea-lanes`); scheduler job `roads_refresh` weekly optional.

### Effort & phased DoD
- **Effort:** Phase 0 **S**; Phase 1 metro arterials **M**.
- **DoD P0:** Legend toggle “Roads” (emphasize motorway/trunk/primary; dim local); honest caption “basemap style / OpenStreetMap via OpenFreeMap”.
- **DoD P1:** One US metro arterial GeoJSON served from worldfeed; CRE dossier can show `nearest_arterial_m` when CRE ships.
- **DoD P2 (optional):** Multi-metro pack + class filters; no routing engine.

### Legal / ops
- OSM **ODbL**: attribution (MapLibre usually surfaces); share-alike if you distribute derived DBs.
- Do not scrape Google Maps road geometries.

---

## 2. Traffic density mapping / estimation

`jormungandrProximity.js` today is **outbreak-near emphasis for flights/vessels**, not road congestion. Do not overload that metaphor without renaming.

### Options (you choose)

| Option | Pros | Cons | Fit |
| --- | --- | --- | --- |
| **A. TomTom / HERE / Google Roads traffic APIs** | Real live congestion; industry standard | Paid keys; ToS restrict redistributing tile bits; poll cost at world scale; desktop always-online | Only for **bbox metro** live mode |
| **B. Historical average speed tiles** (vendor archive or open research) | Stable viz; lower rate pressure | Stale; still often paid; not “live” | OK if labeled historical |
| **C. OSM-derived estimate** (highway class × pop × landuse heuristic heatmap) | Free; writes well to write-through; no ToS scrape risk | **Not real traffic** — must label `quality: estimated` | Constitution-compatible “activity prior” |
| **D. Crowdsourced (Waze Partnership, etc.)** | Rich | Partnership barrier; redistribution limits | Unlikely near-term |
| **E. Skip / stub legend** | Avoids fake certainty | No traffic product | Valid if CRE + pop are priority |

### Fit
- Live paid: thin client + short TTL snapshot table `traffic_cells` keyed by H3/tile + `fetched_at`; scheduler only for **watched metros** (mirror OpenSky credit discipline).
- Estimated: static or rarely refreshed raster/H3 from open inputs; same `/world/traffic` shape with `mode: estimated|live|historical`.

### Effort & phased DoD
- **Effort:** Estimated prior **M**; live metro API **L** (ops + cost).
- **DoD P0:** Document decision; UI refuses silent “green=free flowing” without source.
- **DoD P1 (if C):** H3 “activity prior” from roads×pop; legend “Estimated activity (not live traffic)”.
- **DoD P2 (if A):** One metro live layer behind key; key-absent → empty + status.

### Legal / ops
- Paid APIs: check **cache duration** and **whether map display in commercial desktop is allowed**.
- Scraping Google/Apple traffic UIs: **out of scope / high risk** — do not mirror news-outlet swarm onto these domains.

---

## 3. Population density mapping

Natural choropleth/heatmap sibling to existing nation/subdivision fills; CRE site selection narrative wants this under listings.

### Options (you choose)

| Option | Pros | Cons | Fit |
| --- | --- | --- | --- |
| **A. Kontur Population (HDX)** H3 hex @ 3 km or 22 km global; 400 m for metro | CC BY; designed for maps; matches “density glow”; commercial OK with attribution | Multi-GB at 400 m; need tile/pack strategy; fusion inherits GHSL/HRSL caveats | **Recommended default** |
| **B. WorldPop rasters** | Well known; research-grade | Download/process heavier; licensing per product | Alt global |
| **C. GHSL (JRC) direct** | Authoritative settlement/pop grids | Raw grid plumbing; less “map product” than Kontur | Good upstream cite |
| **D. Census (US ACS / LODES)** | Official US; block-group detail | US-only; geometry join work; update cadence | Best US zoom refinement |
| **E. Hosted pop tiles (Mapbox/MapTiler)** | Easy | Paid; less control; another vendor | Convenience only |

### Fit
- **Serve pattern:** prefer prebuilt **PMTiles / MVT / quantized H3 JSON by z-slice** under `data/population/` (git-LFS or first-run download like OurAirports), not full gpkg in repo.
- `GET /world/pop?bbox=&z=` or static CDN path documented in status; scheduler job `pop_pack_ensure` (7 d check) — no continuous scrape.
- Desktop: `GeoJsonLayer` / `HeatmapLayer` / H3 extrusion; legend under Jormungandr section.

### Effort & phased DoD
- **Effort:** Global low-res (22 km or 3 km) **S–M**; US ACS overlay **M**.
- **DoD P0:** World-scale Kontur 22 km (or 3 km) visible at z≈3–8; attribution in legend/status.
- **DoD P1:** Metro pack 400 m for CRE pilot metros; fade style roads underneath.
- **DoD P2:** Optional US census choropleth at county/tract when zoomed US.

### Legal / ops
- Kontur: **CC BY** — attribute Kontur + cite GHSL/etc. as their docs require.
- Facebook/HRSL lineage where fused: follow Kontur’s attribution notes.
- Do not present as real-time census; stamp `as_of` year on every response.

---

## 4. Commercial real-estate listings (crown jewel)

Multi-source **listings layer** for map markers + dossier. Not a forecast P&L surface.

### Target fields (write-through schema sketch)

```
cre_listings
  id              TEXT PK          -- stable hash(source|source_listing_id) or merge_id
  merge_id        TEXT             -- cross-source dedupe key (nullable until linked)
  source          TEXT NOT NULL    -- loopnet|crexi|costar_public|local|crea|manual|…
  source_listing_id TEXT
  url             TEXT
  title           TEXT
  asset_class     TEXT             -- office|industrial|retail|multifamily|land|hotel|other
  address         TEXT
  city, region, country, postal
  lat, lng        REAL             -- null until geocoded
  price           REAL             -- asking; currency
  currency        TEXT             -- ISO 4217
  cap_rate        REAL             -- nullable; quality flag if inferred
  building_sf     REAL
  lot_sf          REAL
  year_built      INT
  status          TEXT             -- active|pending|off_market|unknown
  raw_ref         TEXT             -- raw_fetches cache_key
  scraped_at      REAL NOT NULL
  first_seen      REAL
  last_seen       REAL
  quality         TEXT             -- official|scraped|estimated|manual
  meta_json       TEXT             -- broker, NOI, zoning blurbs, photos refs…
  provenance_json TEXT             -- pipeline, robots_ok, parse_version
```

Indexes: `(lat,lng)`, `source`, `asset_class`, `last_seen`, `merge_id`.

**API (proposed):**
- `GET /world/cre?bbox=&asset_class=&source=&since=&limit=` → `{ listings, count, generated_at, status }`
- `GET /world/cre/{id}` → full dossier (+ sibling matches by `merge_id`)
- `POST /world/refresh` job keys: `cre_seed_metro`, `cre_scrape_batch`, `cre_geocode_pending`, `cre_dedupe`
- Status: `jormungandr.cre` with per-source last_ok / robots_blocked counts / markets configured

**Desktop:** ScatterplotLayer (price/SF size or asset-class color) + detail chrome dossier (reuse event/nation dossier patterns); legend “CRE” under Jormungandr; never invent prices.

### Sources / deps — pro/con (you choose)

| Source / approach | Pros | Cons | Legal / ops risk | Recommend for |
| --- | --- | --- | --- | --- |
| **Licensed / official APIs** (broker MLS feeds, CREA DDF where eligible, paid CoStar/Crexi partner APIs) | Cleanest provenance; stable schema; constitution-aligned | Cost; contracts; slow sales cycle; Canada CREA has membership rules | Low–medium (contractual) | **Wherever obtainable** |
| **LoopNet public HTML** | Large US inventory; crown-jewel gravity | Aggressive anti-bot; ToS typically forbid scraping; layout churn | **High** | Spike only until legal lock |
| **Crexi public pages** | Strong investment CRE UX; structured-looking cards | Similar ToS/bot posture; rate limits | **High** | Spike / secondary |
| **CoStar-ish public marketing pages** | Brand coverage | CoStar protects data aggressively; scrape ≈ adversarial | **Very high** | Prefer API or skip |
| **Local CRE portals / economic-dev listing pages** | Often friendlier robots; niche coverage | Heterogeneous parsers; sparse | Medium | Good polish sources |
| **Government / open parcel + assessor** (not “listings”) | Open; great for context under CRE | Not asking prices | Low | Enrichment layer |
| **Manual CSV / partner drop** | Honest bootstrap; demos | Not live | Low | **Phase 0 DoD** |
| **RSS/email alert digests** (if a portal offers them) | Fits existing `polite_get` + feedparser muscle | Rare for full CRE cards | Medium | Opportunistic |

**No in-repo clones today** for LoopNet/Crexi. Closest inspirations: worldfeed outlet swarm (robots, spacing, write-through, dedup_key_for), `GoogleMapsClient` for geocode, snapshot APIs for map polling.

### Dedupe across sources
1. Normalize address (USPS-ish lightly) + geocode → grid key (~11 m or building centroid).
2. Soft match: `asset_class` + SF ±10% + price ±15% within 50 m.
3. Prefer `quality: official` fields when merging; keep **all** `sources[]` on the dossier (same honesty as WorldEvent.sources).
4. Never silently drop a source URL — provenance > neat uniqueness.

### Fit with MapLibre / worldfeed / scheduler
- New modules sketched: `jormungandr_cre.py` (facade), `cre_sources/*.py` (one adapter per allowlisted host), reuse `scraper.polite_get` / `RobotsDisallowed`.
- Scheduler: small batches, per-domain delay **≥ outlet default (5 s)** and often much slower; metro allowlist in config; `MEDEROS_CRE=0` kill switch.
- Geocode queue: call Google only on new addresses; heavy use of `geo_cache`.
- Desktop: `worldCreClient.js` poll bbox (viewport) like flights — avoid dumping national inventory to the browser.

### Effort & phased DoD
- **Effort:** schema + fake/manual seed **S**; one polite public source + geocode **M**; multi-source dedupe + dossier polish **L**.
- **DoD P0 (S):** Table + `GET /world/cre` + Desktop markers from **manual/fixture** listings in 1–2 metros; provenance fields populated; legend toggle.
- **DoD P1 (M):** One allowlisted source adapter behind robots check; written through `raw_fetches`; geocode; status honesty; **no** claim of complete market coverage.
- **DoD P2 (L):** Second source + `merge_id` dossier; asset-class filters; optional arterial/pop context chips from layers 1 & 3.
- **DoD P3:** Licensed feed replacement for scrape on that market; scrape becomes gap-fill only.

### Legal / ops risks (CRE — read carefully)
- **ToS / CFAA-class risk** on major CRE portals is real; robots.txt allow ≠ license to build a competing database.
- Prefer: partner APIs, export tools you are entitled to, public open data, and **manual curation** for demos.
- Ops: IP blocks, CAPTCHA, legal letters — design adapters to **fail closed** (skip + ledger error), never escalate evasion (no CAPTCHA farms, no residential-proxy arms race in this codebase).
- Rate limits: metro batch caps; night windows; respect `Crawl-delay`.
- PII: broker contact fields — store minimally; Desktop dossier should not spam-dial.
- Redistribution: even if scraped for internal Mederos World, **re-publishing** full listing DBs may be a separate rights issue.

**Recommended CRE posture until you lock:** **Hybrid, US metros first**, P0 fixtures shipping map UX while legal posture for LoopNet/Crexi is decided; do not scale scrape fleet pre-lock.

---

## Recommended build order

CRE is the crown jewel for *product identity*, but sequencing should maximize honest map richness per engineering week.

| Phase | Ship | Why |
| --- | --- | --- |
| **W0** | **Roads P0** (style emphasize) + **Pop P0** (Kontur low-res) | Cheap wow; zero scrape risk; proves legend/toggle + attribution patterns |
| **W1** | **CRE P0** (schema, `/world/cre`, fixtures, markers, empty dossier chrome) | Crown jewel UX shell without legal exposure |
| **W2** | **CRE ingest lock** (user decision) + **Roads P1** arterials for pilot metros | Analytic join ready when listings land |
| **W3** | **CRE P1** first source (per lock) + **Pop P1** metro pack | Listings + density narrative |
| **W4** | **CRE P2** dedupe + second source / licensed path | Crown jewel depth |
| **W5+** | Traffic only after A/C choice; default skip live paid until CRE stables | Avoid expensive distraction |

**What to ship first for “map looks rich”:** **population density + style roads** (often same week).  
**What to protect as crown jewel:** CRE schema, dossier, multi-source provenance — even if fixtures come before scrapers.

---

## Tiny spikes (optional validation — not this doc’s implementation)

Only if useful later; keep each &lt;1 day:
1. List OpenFreeMap dark style layer ids matching highway classes (paint spike).
2. Download Kontur 22 km sample → one GeoJsonLayer in WorldView behind a flag.
3. `robots_allowed` probe for 1–2 CRE host URL patterns (no parsers, no bulk) — record outcome in ledger mindset.
4. Hand-enter 20 fixture CRE rows → `/world/cre` + markers (proves schema).

---

## Open decisions checklist (for you)

- [ ] Roads: **A style-only** vs **A+B analytic metro**?
- [ ] Traffic: **E skip**, **C estimated**, or **A paid metro**?
- [ ] Population: **Kontur** resolution ladder (22 km → 3 km → 400 m metros)?
- [ ] CRE: **hybrid vs scrape-only vs API-only**?
- [ ] CRE v1 markets: e.g. **DFW, Atlanta, Phoenix, Chicago, LA** (pick 2–3)?
- [ ] CRE legal gate before LoopNet/Crexi parsers?

---

## Appendix — existing seams to extend (file touch map)

| Concern | Extend |
| --- | --- |
| Store / write-through | `worldfeed/store.py` |
| Polite fetch | `worldfeed/scraper.py`, `common.py` |
| Jobs | `worldfeed/scheduler.py` `JOBS` |
| HTTP | `worldfeed/routes.py` + `GET /world/status` |
| Contract docs | `WORLD_DATA_PLATFORM.md` |
| Map style | `mobile/src/world/worldMapStyle.js` |
| Layers / legend | `mobile/src/world/WorldView.jsx`, new `jormungandrRoads.js` / `jormungandrPop.js` / `jormungandrCre.js` |
| Geocode | `google_maps_client.py` / `geo_cache` |
| Inspiration (process, not CRE code) | outlet swarm digestion + shipping static GeoJSON path |

*End of plan.*
