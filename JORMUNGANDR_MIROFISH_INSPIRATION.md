# Jormungandr ← MiroFish inspiration

*Scouted 2026-08-03 (first pass @ `96096ea`). Second pass 2026-08-03 @ `a97ba4f` (+51). Ideas only — no vendor of MiroFish/OASIS/Zep code. Cross-link: [`JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`](./JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md) · clone index: [`JORMUNGANDR_INSPIRATION_REPOS.md`](./JORMUNGANDR_INSPIRATION_REPOS.md).*

---

## 1. What MiroFish is / where / stack

| | |
| --- | --- |
| **Product** | Multi-agent “swarm” prediction sandbox: seed docs → knowledge graph → persona agents → dual social sims → LLM report + chat |
| **Canonical clone** | `C:\Users\epiki\Documents\Development\kalshai\inspiration_repos_and_sources\MiroFish` (also a worktree copy under `.claude\worktrees\…`) |
| **Upstream** | https://github.com/666ghj/MiroFish (first pass `96096ea` → second pass `a97ba4f`) |
| **License** | **AGPL-3.0** (root + backend) — viral for networked services if code is copied |
| **Frontend** | Vue 3 + Vite + vue-router + vue-i18n + **D3** force graphs (`GraphPanel.vue`) |
| **Backend** | Python 3.11–3.12, Flask, OpenAI-compatible LLM client, **Zep Cloud** GraphRAG, **CAMEL OASIS** (`camel-oasis` / `camel-ai`) for Twitter+Reddit twin sims |
| **Hard deps** | `LLM_API_KEY` + `ZEP_API_KEY` (cloud). High token burn; README warns start with &lt;40 rounds |
| **Workflow (5 steps)** | Graph build → Env/persona setup → Dual-platform simulation → ReportAgent → Deep interaction (chat / interview) |
| **Fancy loop** | Graph | Split | Workbench layouts; live graph refresh while sim runs; ROUND/TIME/ACTS dual timelines; ReportAgent tools (`insight_forge`, `panorama_search`, `interview_agents`); temporal Zep edges (`valid_at` / `expired_at`) |

**Fit vs Jormungandr:** MiroFish sells *narrative emergence* (“predict anything”). Jormungandr sells *geographic contagion + Causal Sim fans + Muse honesty* (Brier, not P&L; skips stay skips). Steal **interaction patterns and scaffolding UX**, not the prediction epistemology or the AGPL/cloud stack.

---

## 2. Portable fancy ideas (pro/con) → Jormungandr seams

### A. Graph | Split | Workbench layout triad — **UI**

| Pro | Con |
| --- | --- |
| One-click maximize left (structure) / right (work) / equal split; tiny code surface | Vue pattern must be re-expressed in React/Desktop WorldView |
| Matches planned “World Lab” (map + scrubber + Truth) from integration plan §P3 | Easy to overload first viewport if all three fight for chrome |
| Immediate product polish without new backend | No data intelligence by itself |

**Seam:** Desktop `WorldView.jsx` / `WorldSimPanel.jsx` → modes **Map** · **Split** · **Muse/Truth** (Light Muse + Brier chips). Optional maximize graph ↔ maximize Causal Sim fans.

---

### B. Dual-stream action timeline + platform status chips — **sim / feed**

| Pro | Con |
| --- | --- |
| ROUND / TIME / ACTS chips + interleaved event lane feels “alive” | MiroFish lanes = social posts; ours must be *observable* world facts / sim steps, not LLM chatter |
| Shared clock ↔ our existing contagion scrubber + Wasm bar stepping | Need honest filtering: no invented spikes; empty lanes when unmapped |
| Maps cleanly to flights vs vessels, feed vs fan, or corridor events vs market tape | Dual lane without density caps turns into doomscroll |

**Seam:** World feed + Causal Sim `tDays` scrubber; corridor / flight / vessel pulses; optional secondary lane for Muse signal flips under `scenarioKey`.

---

### C. Force graph + entity legend + detail dock + live refresh — **viz**

| Pro | Con |
| --- | --- |
| Type-colored nodes, link highlight, zoom/drag, side detail (uuid / props / temporal facts) | Geographic MapLibre+deck.gl already owns space — abstract graph is a *second* viz, not a replacement |
| “Graph memory updating” cue during build/sim is excellent status storytelling | Full MiroFish graph is Zep Cloud IDs — do not couple |
| Temporal edge tint (`valid_at`→`expired_at`) rhymes with Causal Sim edge decay | D3 force layouts fight large graphs; need lod / filter |

**Seam:** Causal network / contagion abstract graph panel *beside* the map; node click → claim + Brier if resolved (already in overlay legend plan). Refresh while `POST /world/simulate` run progresses — same 30s poll idea MiroFish uses.

---

### D. Five-step “sandbox wizard” (seed → ontology → run → report → interrogate) — **UI / data**

| Pro | Con |
| --- | --- |
| Clear mental model for first-time World Lab users | MiroFish steps assume LLM persona factory — we must gate each step on real seeds / `sim_seed` |
| History database of runs ≈ our simulate runs history | Over-wizarding blocks power users who already have `scenarioKey` |
| Maps to: Feed select → Sim params → Scrub → Light Muse → Truth | “Prediction Report” title framing risks fake certainty |

**Seam:** World Lab checklist: events → `WorldContext` → fan scrub → Muse run/evolve → TruthReport / Brier rollup. Rename “Prediction Report” → **Truth / Calibration report**.

---

### E. Post-run “interview” / multi-perspective interrogation — **swarm-shaped UX (without OASIS)**

| Pro | Con |
| --- | --- |
| Asking a node / regime / strategy “what moved you?” is delightful | LLM interviewing simulated agents ≠ calibrated forecast; Constitution conflict if sold as truth |
| Tool loop (`interview` + panorama) can wrap **existing** Truth + ForecastHost | Easy to reintroduce social-sim agents nobody asked for |
| Batch interview → summary is a good ReportAgent pattern | Offline-hostile if chat requires cloud LLM |

**Seam:** Muse Light chat that is **tool-bound** to `WorldContext`, resolved claims, and Brier numbers only — never free-form “the market will…”. Optional “interview contagion node” = explain fan series + provenance, not invent narrative.

---

### F. ReportAgent ReACT toolbelt (`insight_forge` / `panorama` / `quick_search`) — **data / report**

| Pro | Con |
| --- | --- |
| Structured retrieval before prose beats pure LLM hallucination | MiroFish tools query Zep graph; ours should query feed + sim runs + ledger |
| Sub-query fan-out is a solid pattern for regime docs | High cost; must be opt-in Desk-side |
| Sectioned progressive report UI (Step5) is strong | Narrative reports without resolution scores fail Constitution |

**Seam:** Enrich `TruthReport` / ReportCard under a `scenarioKey` with tools over WorldFeedStore + sim series + Honest Ledger — citations required; unsettled claims show **skip / unresolved**, never fake p.

---

## 3. Recommended adoption order

| Order | Steal | Why first | Conflict with Constitution |
| --- | --- | --- | --- |
| **1** | **A — Map \| Split \| Muse layout triad** | Max wow / min stack risk; unblocks World Lab chrome; &lt;1h spike candidate on Desktop | None (pure chrome) |
| **2** | **B — Dual-lane scrub timeline** | Reuses scrubber; makes feed + fan feel co-temporal | Must not invent events; empty = honest |
| **3** | **D — Wizard / checklist rename to Truth path** | Onboards without new engines | Ban “Prediction Report” certainty copy |
| **4** | **C — Abstract causal graph dock** | Complements map; click→Brier already planned | Don’t bind Zep; prefer local / fincog graph |
| **5** | **F then E — Tool-bound Truth report + interrogation** | Only after calibration chips exist | LLM prose last, Brier first |

**Steal first pick:** Layout triad remapped to **Map · Split · Muse/Truth**.

**Shipped (Desktop, 2026-08-03):** `worldLayout.js` + WorldView mode toggle · workbench hosts Causal Sim / Light Muse / Evolve / Truth / Brier / reliability · Playwright `world-layout-*` · no default-landing change · no AGPL code.

**Shipped (2026-08-04 UI follow-on):** persisted sim-run browser (`GET /world/simulate/runs` + local ring) · dual-lane scrub + feed pins (pattern **B**, reimplemented) · AIS/bridge honesty chrome · mobile manage strip under detail · nation/outlet/ops sheet. Still no AGPL vendor.

**Optional tiny spike (&lt;1h):** ~~Desktop-only mode toggle on WorldView (Map / Split / Muse) mirroring MiroFish’s graph/split/workbench — no new packages, no AGPL code.~~ → **done**.
---

## 4. Explicit non-ports

| Item | Why not |
| --- | --- |
| **Vendoring MiroFish source** | AGPL-3.0 — network copyleft risk for Mederos / Kalshai products |
| **Zep Cloud GraphRAG pipeline** | SaaS key, offline-hostile, entities leave machine; not our WorldFeed contract |
| **OASIS / camel-ai Twitter+Reddit swarm** | Heavy LLM burn, social-sim ontology, coupled to MiroFish IPC; wrong epistemic object for Causal Sim |
| **“Predict anything / win decisions after countless sims” framing** | Conflicts with Brier not P&L and no fake certainty |
| **LLM persona factories inventing agents from PDFs** | Invented actors ≠ worldfeed events; fake certainty |
| **Free-chat ReportAgent as product truth** | Narrative without resolution scoring; use TruthReport + Ledger instead |
| **Filesystem IPC sim control as-is** | Tied to OASIS runner processes; we already have `/world/simulate` + Desktop clients |
| **China-specific activity hour tables / social action vocab as defaults** | Domain wrong for geographic contagion / markets (pattern of diurnal multipliers OK later, tables no) |

---

## 5. Quick reference — MiroFish → our nouns

| MiroFish | Jormungandr / Muse |
| --- | --- |
| Seed upload + ontology | World feed events + `sim_seed` |
| Zep graph | Contagion / causal graph (local or fincog) |
| Dual OASIS platforms | Dual lanes: feed observables ↔ sim fan / corridors |
| ROUND scrub | `tDays` / Wasm bar scrub |
| Prediction Report | TruthReport + Brier chips |
| Interview agents | Tool-bound explain node / claim / strategy |
| God’s-eye inject | Mag mult / remediation / counterfactual (already on sim panel) — not LLM persona puppetry |

---

## 6. Second pass (2026-08-03) — MiroFish delta `96096ea` → `a97ba4f`

**Pull:** ff-only on existing clone (51 commits). Mostly Zep/ontology hardening, Docker ARM, star-history CI — **not** a new product surface. Still AGPL-3.0; still do not vendor.

### New portable ideas (re-implement; do not copy)

| ID | Pattern | Evidence in delta | Jormungandr seam | Steal? |
| --- | --- | --- | --- | --- |
| **G** | **Fail-fast wizard polling** — one `handlePrepareFailure` stops all pollers + emits error status | Step2: prepare/config/profiles failed → stop polling | World Lab prep / `/world/simulate` start: never leave scrubbers spinning on dead runs | **Yes — reliability chrome** |
| **H** | **Terminal failure prioritized over “looks done”** | Step3: `runner_status === 'failed'` before completed/stopped; UI stops poll | Causal Sim / Wasm run status: failed beats stale “completed” heuristics | **Yes** |
| **I** | **Ingestion / publish barrier before terminal UI state** | Comment + runner: terminal published only after Zep barrier drains | Don’t show TruthReport complete until ledger + series are flush; “STOPPING” ≠ ready | **Yes (concept)** — own barrier over local stores, not Zep |
| **J** | **Strip fabricated tool_result / hallucinated tool logs from LLM prose** | ReportAgent `_strip_fake_tool_result`; tests for sanitizer | Muse Light / Truth chat: only host-executed tools count; strip fake citation blocks | **Yes — Constitution-critical** |
| **K** | **Graph build reuse short-circuit** | `reused && graph_id` → load without new poll storm | Cache `sim_seed` + WorldContext graph fingerprints; skip rebuild | **Yes** |
| **L** | **Local timezone on history cards** | HistoryDatabase local date/time; don’t drop duplicate user messages | Run-history UI + chat transcript honesty | Nice-to-have |
| **M** | Cap pager / max_items on graph edge fetch | Unbounded edge fetch memory fix | Local contagion graph loaders need hard caps + lod | Yes if we ship abstract graph |

**Still not new product UX:** layout triad / dual timeline / D3 graph (first-pass A–C) unchanged in meaningful ways. Delta is reliability + cloud-contract glue.

### Second-pass adoption delta

| Order | Add after first-pass A/B | Why |
| --- | --- | --- |
| **1a** | **G + H** fail-fast + failed-wins polling | Cheap; prevents lying World Lab UX |
| **1b** | **J** tool-result sanitizer (our tools only) | Required before any Muse report chat ships |
| later | **I** local publish barrier | After simulate persistence is real |

### Second-pass non-ports (extra)

| Item | Why not |
| --- | --- |
| Zep lifecycle / ontology contract / edge paging code | AGPL + SaaS lock-in |
| GPT-5 chat-compat helpers verbatim | AGPL; re-express against Muse host if needed |
| Fabricated-tool strip regex as-copied | Reimplement against our tool envelope; don’t paste ReportAgent |
| Star-history / README cosmetics | Noise |

---

## 7. Cross-repo steal matrix (second pass companions)

Clones live under `C:\Users\epiki\Documents\Development\kalshai\inspiration_repos_and_sources\` — see [`JORMUNGANDR_INSPIRATION_REPOS.md`](./JORMUNGANDR_INSPIRATION_REPOS.md). Prefer **MIT/Apache** for deep mine; AGPL/GPL/unlicensed = **read-only concepts**.

| Steal | Source (license) | Seam | Priority | Vendor code? |
| --- | --- | --- | --- | --- |
| Map · Split · Muse layout triad | MiroFish **A** (AGPL) | WorldView modes | P0 chrome | **No** |
| Dual-lane scrub timeline | MiroFish **B** (AGPL) | feed ↔ fan scrub | P0 | **No** |
| Fail-fast + failed-wins poll | MiroFish **G/H** (AGPL) | simulate status | P0 reliability | **No** |
| Fabricated-tool strip | MiroFish **J** (AGPL) | Muse Light / Truth | P0 honesty | **No** |
| Multi-scenario overlay + error bands | **spkmc** (MIT) | Causal Sim fan bands | **P0 viz** | Ideas OK; rewrite — **landed** Desktop World (`jormungandrUncertaintyBands.js` + sim dock spark + map halo; reimplemented MIT concept) |
| Scenario A/B comparison + cascade depth/width | **Prophet** (MIT) | fan compare / contagion metrics | **P0 analytics UX** | Ideas OK |
| Timeline sparkline + emergent event pins | **Prophet** TimelinePanel (MIT) | `tDays` scrub + event markers | P1 | Ideas OK |
| Live WebSocket sim store | **Prophet** `useSimulationSocket` (MIT) | Desktop poll → push optional | P2 | Ideas OK |
| Normalize → fuse nearby watchpoints → confidence | **GSID** IntelligenceEvent (no license) | WorldFeedStore fusion | **P0 data** | **Read only** — reimplement |
| Heuristic first paint → optional LLM upgrade w/ fallback | **GSID** (no license) | insight strip without blocking map | P1 | Reimplement |
| Split.js multi-pane + persisted layout + pulse markers | **OSINT-War-Room** (MIT) | World Lab panels / GDELT-like pulses | P1 chrome | Ideas OK (Leaflet≠MapLibre) |
| Layer catalog + dual 3D/flat map + site variants | **worldmonitor** (AGPL) | deck.gl layer IA only | P1 concepts | **No code** |
| Intervention builder + 3D network playback | **EpiVirus** (unlicensed) | remediation UI / node playback | P2 | **Read only** |
| ABM scheduler / Solara viz components | **mesa** (Apache-2.0) | agent stepping metaphors | P2 | Can study; unlikely direct dep |
| Gillespie / network epidemic process API | **epydemic** (GPL-3.0) | contagion math vocabulary | P3 reading | **No vendor** |

### Top 3 steals (all clones)

1. **spkmc multi-scenario fan overlay + uncertainty bands** — Causal Sim’s core “wow” without social-sim LLM burn (MIT).
2. **GSID-style feed normalize + spatial fuse + confidence** — WorldFeed honesty before narrative (reimplement; unlicensed upstream).
3. **Prophet cascade metrics + scrub timeline event pins** *or* MiroFish **G/H/J** reliability+sanitizer — pick analytics chrome (MIT) vs integrity chrome (AGPL patterns reimplemented) depending on layout sibling’s week.

### Explicit do-not-vendor (global)

- Any **AGPL** tree as product source: MiroFish, worldmonitor platform, AgentTorch (not cloned this pass; same poison).
- **GPL** epydemic as a linked library.
- Unlicensed EpiVirus / GSID **source files**.
- OASIS / camel / Zep Cloud pipelines.
- “Predict anything / win decisions” marketing copy.
- Polymarket/VIX/novelty widgets that invent certainty without Brier.
