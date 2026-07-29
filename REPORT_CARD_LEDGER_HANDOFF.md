# Initiative 5 — Report Card / Honest Ledger (handoff)

**Date:** 2026-07-28 · Priority 3

## muse-script API / types

| Surface | Location |
|--------|----------|
| `ReportCard` + `fromTruthReport` / `toDyn` | `musescript/evo/rigor/ReportCard.hx` |
| `HonestLedger` + entry helpers | `musescript/evo/rigor/HonestLedger.hx` |
| `LedgerDisposition` (`GO` / `CAUTION` / `NO-GO`) | `musescript/evo/rigor/LedgerDisposition.hx` |
| Attach on instrumented runs | `result.reportCard` via `attachTruthReport` |
| `MuseRuntime.buildReportCard(payload)` | Truth Report → Report Card |
| `MuseRuntime.seedRobustnessSweep(source, bars, opts)` | median-not-max seed check; optional updated card |
| `MuseRuntime.ledgerEntryFromTruth(payload)` | serializable ledger entry (IDE persists) |

Schemas: `mederos.reportCard.v1`, `mederos.honestLedger.v1` / `.entry`.

## Studio UI / persistence

| Piece | Path |
|-------|------|
| Report Card panel | `mobile/src/lab/ReportCardPanel.jsx` |
| Types / fallback builder | `mobile/src/lab/reportCardTypes.js` |
| Honest Ledger panel | `mobile/src/lab/HonestLedgerPanel.jsx` |
| localStorage store | `mobile/src/lab/honestLedger.js` (`mederos.studio.honestLedger.v1`) |
| Wired in | `StrategyStudio.jsx` (after Truth Report + Determinism badge) |
| Client APIs | `museRuntimeClient.js` → `buildReportCard`, `seedRobustnessSweep`, `ledgerEntryFromTruth` |

Every successful Run with a Truth Report appends a ledger entry (GO / CAUTION / NO-GO). Duplicate digest+seed+verdict within recent entries is skipped.

## Verify

1. `haxe build-runtime.hxml` → copy `build/js/muse-runtime.js` → `mobile/src/lab/`
2. `haxe build-projection-host-tests.hxml && node build/js/tests-projection-host.js` — expect `testReportCard*` / `testHonestLedgerDispositions` OK
3. Strategy Studio → Run → `data-testid="studio-report-card"` + `studio-honest-ledger`
4. Expand ledger → entry for this run; NO-GOs counted equally
5. Report Card → **Check seeds** (single-tape) → seed slot leaves `pending`

## Gaps (intentional extension points)

- Full multi-instrument universe robustness (pass `instruments[]` into Report Card / opts)
- Automatic seed sweep on every run (opt-in button only — cost)
- Per-symbol OOS metrics from panel runs
- Share-card artwork for Report Card (Truth Report share path untouched)
