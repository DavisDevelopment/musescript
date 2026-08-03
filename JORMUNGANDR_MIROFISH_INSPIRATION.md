# Jormungandr ← MiroFish inspiration

*Scouted 2026-08-03. Ideas only — no vendor of MiroFish/OASIS/Zep code. Cross-link: [`JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md`](./JORMUNGANDR_MUSESCRIPT_INTEGRATION_PLAN.md).*

---

## 1. What MiroFish is / where / stack

| | |
| --- | --- |
| **Product** | Multi-agent “swarm” prediction sandbox: seed docs → knowledge graph → persona agents → dual social sims → LLM report + chat |
| **Canonical clone** | `C:\Users\epiki\Documents\Development\kalshai\inspiration_repos_and_sources\MiroFish` (also a worktree copy under `.claude\worktrees\…`) |
| **Upstream** | https://github.com/666ghj/MiroFish (head at scout: `96096ea`) |
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

**Optional tiny spike (&lt;1h):** Desktop-only mode toggle on WorldView (Map / Split / Muse) mirroring MiroFish’s graph/split/workbench — no new packages, no AGPL code.

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
