# Jormungandr inspiration repo index

*Second concept-borrowing pass 2026-08-03. Clones under `C:\Users\epiki\Documents\Development\kalshai\inspiration_repos_and_sources\`. Ideas / UX patterns only unless license is permissive **and** we deliberately rewrite. Detailed MiroFish notes: [`JORMUNGANDR_MIROFISH_INSPIRATION.md`](./JORMUNGANDR_MIROFISH_INSPIRATION.md).*

**Policy:** Prefer MIT / Apache / BSD for deep mine. AGPL / GPL / missing license = **read-labeled**; never paste into product trees.

| Clone path | Upstream | License | Why it matters for Jormungandr | Steal candidates | Do not |
| --- | --- | --- | --- | --- | --- |
| `...\MiroFish` @ `a97ba4f` | [666ghj/MiroFish](https://github.com/666ghj/MiroFish) | **AGPL-3.0** | Original swarm sandbox UX scout; layout triad, dual timeline, report tools | Patterns **A–M** in MiroFish doc (reimplement) | Vendor source; Zep; OASIS; “predict anything” |
| `...\spkmc` @ `457ef0d` | [mcaxtr/spkmc](https://github.com/mcaxtr/spkmc) | **MIT** | Network SIR experiment sandbox with dashboard + scenario JSON | Multi-scenario overlays, error bands, experiment JSON → run → compare | Blind-copy Plotly/Streamlit chrome into Desktop |

**Landed (reimplemented MIT concept):** Desktop Causal Sim uncertainty bands — `mobile/src/world/jormungandrUncertaintyBands.js` spark panel (p10–p90) + choropleth confidence halo on scrubbed T; optional dual baseline/CF overlay. No Plotly / no vendor source.
| `...\Prophet` @ `5b9be70` | [showjihyun/Prophet](https://github.com/showjihyun/Prophet) | **MIT** | Diffusion ABM wind-tunnel; React timeline/graph better aligned than MiroFish for cascade UX | Cascade depth/width, A/B ComparisonPage, TimelinePanel event pins, GraphLegend | LLM persona factory as product truth; OASIS-shaped ontology |
| `...\OSINT-War-Room` @ `17caed4` | [Hue-Jhan/OSINT-War-Room](https://github.com/Hue-Jhan/OSINT-War-Room) | **MIT** | Situation-room map + feeds + markets in one shell | Split.js persisted panes, GDELT pulse markers, modular bottom panels | Novelty indexes (pizza/VIX) sold as calibrated forecasts |
| `...\Global-Situation-Intelligence-Dashboard` @ shallow | [Acnologia7021/…](https://github.com/Acnologia7021/Global-Situation-Intelligence-Dashboard) | **None (unlicensed)** | Tiny map + fused watchpoints + scenario cards | `IntelligenceEvent` normalize/fuse/confidence; heuristic-first insights | Copy source; ship unverified `probability` as Muse p |
| `...\worldmonitor` @ `ab798e6` | [koala73/worldmonitor](https://github.com/koala73/worldmonitor) | **AGPL-3.0** (SDKs MIT separately) | Production geo intel dashboard; 56 layers; dual 3D/flat; site variants | Layer IA, timeRange, ADS-B/AIS feed pairing concepts | Vendor dashboard/server; trademark; AGPL platform |
| `...\EpiVirus` @ `a137d7c` | [zainabraza06/EpiVirus](https://github.com/zainabraza06/EpiVirus) | **None (unlicensed)** | SEIRD + interventions + Three.js network playback | Intervention builder UX; per-node state playback; chart suite IA | Vendor any source files |
| `...\mesa` @ shallow | [projectmesa/mesa](https://github.com/projectmesa/mesa) | **Apache-2.0** | Canonical Python ABM toolkit + browser viz | Scheduler metaphors; Solara/Jupyter viz patterns | Force Mesa runtime into Wasm stack without need |
| `...\epydemic` @ shallow | [simoninireland/epydemic](https://github.com/simoninireland/epydemic) | **GPL-3.0** | Network epidemic process framework (Gillespie etc.) | Vocabulary / experiment-management ideas only | Link or vendor GPL code |

## Not cloned this pass (noted)

| Project | License | Note |
| --- | --- | --- |
| [AgentTorch/AgentTorch](https://github.com/AgentTorch/AgentTorch) | **AGPL-3.0** | Large-population / epidemic LPM — valuable science, same AGPL poison as MiroFish |
| STITCH / sir_simulator / GenSim / Agentopia | MIT-ish or academic | Lower priority; Prophet + spkmc already cover diffusion/SIR UX |
| GeoSynth / aegis-web | unknown / MIT-candidate | Overlap with GSID + OSINT-War-Room; skip unless feed fusion needs another sample |

## Deep-mine order (if time-boxed)

1. **spkmc** + **Prophet** (MIT) — fan overlays, cascade metrics, timeline pins  
2. **OSINT-War-Room** (MIT) — pane chrome / pulse markers on MapLibre terms  
3. **GSID** (unlicensed) — redesign `IntelligenceEvent` → WorldFeed contracts from scratch  
4. MiroFish second-pass **G/H/J** — reimplement fail-fast + sanitizer  
5. worldmonitor — **sketch layer taxonomy only**; zero code transfer  

## Clone maintenance

```powershell
$root = "C:\Users\epiki\Documents\Development\kalshai\inspiration_repos_and_sources"
Push-Location "$root\MiroFish"; git fetch origin; git pull --ff-only; Pop-Location
# shallow clones: re-fetch tip
foreach ($n in "spkmc","Prophet","OSINT-War-Room","worldmonitor","mesa","epydemic","EpiVirus","Global-Situation-Intelligence-Dashboard") {
  Push-Location "$root\$n"; git fetch --depth 1 origin; Pop-Location
}
```
