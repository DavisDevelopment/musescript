# Truth Report — IDE handoff (muse-script → kalshai/mobile)

**Date:** 2026-07-28 · Initiative 1 (Honest Backtest)

muse-script exposes the Truth Report **data contract** and attaches it on every
instrumented `MuseRuntime.run` / `runPanel` / `runWasm` result. Strategy Studio
consumes `result.truthReport` and renders the traffic-light UI.

## Consume from muse-script

- Types: `musescript.evo.rigor.TruthReport` + `TruthVerdict` (`Robust` / `Fragile` / `Coin-flip` / `Overfit`)
- JSON: `TruthReport.toDyn()` on run results as `truthReport`, or `MuseRuntime.evaluateTruthReport(payload)`
- Trials API on MuseRuntime: `trialsReset` / `trialsRecord` / `trialsSetCount` / `trialsGetCount`
- Run opts: `nTrials`, `nullSharpe`, `purgeEmbargoApplied`, `oosHeld`, `pbo`, `skipTruthReport`,
  **`honestOos`** (Studio default), `oosFrac` (0.25), `embargoBars` (20)
- When `honestOos: true`: nested OOS re-run on purge/embargo slice → Truth Report scored OOS-only;
  full-tape chart/metrics unchanged; `result.oosSplit` / `oosEquity` attached
- PBO: `MuseRuntime.estimatePbo(perf[strategy][slice])` — never invent; Studio `studioPboCloud.js`
  accumulates session variants and passes `opts.pbo` when the cloud is legal (≥2 variants × 4 slices)
- Null baseline (Studio default): buy-and-hold of close series when `nullSharpe` omitted
- Trials: IDE `studioTrialsSession.js` fingerprints source+params; passes `nTrials` each run

## Landed in `kalshai/mobile`

1. **1.1** Strategy Studio Run path → `truthReport` on every successful client-side backtest.
2. **1.2** `TruthReportPanel.jsx` — verdict badge + gate dots + plain-language `reasons`.
3. **1.3** `studioTrialsSession.js` — sessionStorage distinct-variant counter → `nTrials`.
4. **1.5** Share card — PNG card (verdict + gates + seed/digest) + JSON clipboard export.
5. **Purge/embargo OOS** — `honestOos: true` default via `museRuntimeClient` → real `oosHeld`.
6. **Live PBO** — session trial cloud; UI shows `n/a` until legal (never faked).
7. **Autoresearch champions** — client-side Truth Report on applied champions (`StudioAutoresearch`).

Refresh engine after Haxe changes:
```
(in muse-script)  haxe build-runtime.hxml
cp build/js/muse-runtime.js ../../mobile/src/lab/muse-runtime.js
```

## Still open / soft

| Gap | Owner | Notes |
|-----|-------|-------|
| Full Fitness buy-hold genome | optional | Studio uses close-based BH Sharpe (same economics); Fitness genome path remains for evo CLIs. |
| MuseNotebook cell Truth Report panel | mobile | Notebook runs attach `truthReport` via runtime; full panel UI still Run/Research-first. |
| Optimizer trial-cloud PBO (server) | later | Client session cloud covers Studio; Autoresearch server CSCV matrix not yet piped. |
| Forecast-host WASM | separate init | Not required for Truth Report; Initiative 2. |

## Do not regress

Hardened instrument (min-trades on candidates, DSR, PBO, OosVerdict GO/NO-GO) stays authoritative; Truth Report is the IDE-facing traffic-light on top of it.

## Verify

1. Open Strategy Studio → Run sample strategy.
2. Expect `data-testid="studio-truth-report"` with verdict; OOS footnote when `oosSplit.applied`.
3. Gates: OOS / purge-embargo should pass (no “IDE should pass purgeEmbargoApplied” reason).
4. Tweak a `@param` slider twice → after ≥2 variants, PBO may appear (or stay n/a with clear copy).
5. Click “share card” → PNG on clipboard (or download); “copy JSON” → `mederos.truthReport.v1`.
6. Research mode → apply champion → `data-testid="studio-champ-truth"` Truth Report panel.
7. Console: `result.truthReport.oosHeld === true`, `result.oosSplit.applied === true`.
