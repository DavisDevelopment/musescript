# Offline EwPhiParams finetune

Louisli-style insight: every φ decimal is a named weight in `EwPhiParams`, finetuneable on modern data. Hard impulse/corrective rules stay fixed; only soft tolerances and target tables are learned offline.

## Pipeline

```text
bars (CSV or synthetic)
    → EwFinetuneCli export
    → build/ew_finetune_features.json
    → tools/ew_phi_finetune.py
    → build/finetuned_phi.json
    → EwPhiParams.loadFromJsonFile + setCurrent
```

## 1. Build CLI

```bash
haxe build-ew-finetune.hxml
```

## 2. Export features

Synthetic smoke fixture:

```bash
node build/js/ew-finetune.js export-synthetic --out build/ew_finetune_features.json --horizon 5
```

Historical OHLCV CSV (same format as `OhlcvCsv`):

```bash
node build/js/ew-finetune.js export --csv data/bars.csv --out build/ew_finetune_features.json --horizon 10
```

Each row includes pivot metadata, top lattice hypothesis label/score, W2/W1 and W4/W3 ratios, soft hits, guideline subscores, and forward return over the horizon.

## 3. Finetune (Python)

Coordinate descent over soft scalars + W2/W4 retrace targets — no PyTorch required:

```bash
python tools/ew_phi_finetune.py --in build/ew_finetune_features.json --out build/finetuned_phi.json
```

**Loss (v1):** minimize negative alignment between recomputed soft fib hits and signed forward return on impulse/zigzag labels. Hard rule thresholds are excluded from the search space.

## 4. Load into Muse

CLI:

```bash
node build/js/ew-finetune.js load --in build/finetuned_phi.json
```

Programmatic (Node / JVM sys target):

```haxe
var p = EwPhiParams.loadFromJsonFile("build/finetuned_phi.json");
EwPhiParams.setCurrent(p);
```

Or via map round-trip:

```haxe
var m = PhiParamsDump.loadMapFromJsonFile("build/finetuned_phi.json");
EwPhiParams.setCurrent(EwPhiParams.loadFromMap(m));
```

## Tests

```bash
haxe build-geom-ew-tests.hxml && node build/js/tests-geom-ew.js
```

`TestEwPhiFinetune` covers export smoke, `applyMap` / `bestHit` behavior, and JSON load.

## Never in hot path

`EwFinetuneExport`, `EwFinetuneCli`, and `ew_phi_finetune.py` are batch/offline only — never call from `MuseIndicator.update()`.
