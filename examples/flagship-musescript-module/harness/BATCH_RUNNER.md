# Warm batch-eval runner — how to use

Kills the per-cell Node cold-start tax documented in
[`CURSOR_BATCH_RUNNER_SPEC.md`](../../../CURSOR_BATCH_RUNNER_SPEC.md).

## Build

From repo root:

```powershell
haxe build-cli.hxml      # gene-runner.js (single-shot + --jobs + legacy --batch)
haxe build-batch.hxml    # batch-runner.js (stdin NDJSON multi-tape warm runner)
```

`eval.ensure_batch_runner()` builds `batch-runner.js` on demand when missing, and
falls back to `node gene-runner.js --jobs -` if the dedicated binary is absent.

## Job / result protocol

**stdin** — one NDJSON job per line:

```json
{"id":"eval_3m|SPY|strat","source":"<full stitched .ms>","tape":"…/tapes/eval_3m/SPY.csv","execution":"next-open","costBps":10,"seed":42}
```

**stdout** — one NDJSON result per job as it completes (same metrics shape as
single-shot `gene-runner`):

```json
{"id":"eval_3m|SPY|strat","ok":true,"sharpe":0.42,"maxDrawdown":0.11,"trades":4,"winRate":0.5,"finalEquity":103200,"cached":true}
```

Caches inside one process lifetime:

| Cache | Key | Effect |
|---|---|---|
| Strategy compile | SHA-256(source) + target | Buy-hold + stitched strategy compile once |
| Tape parse | `path \\x1e symbol` | CSV read/parse once per tape |

## Python API

```python
from eval import run_gene_batch, stitch_source, buy_hold_source

jobs = [
    {"id": "a|strat", "source": stitch_source(path), "tape": str(tape), "execution": "next-open", "costBps": 10},
    {"id": "a|bh", "source": buy_hold_source(), "tape": str(tape), "execution": "next-open", "costBps": 10},
]
results = run_gene_batch(jobs)  # dict[str, Metrics]
```

Optional `on_result(job_id, Metrics, raw_dict)` fires as each line arrives —
`score_probe.py` / `viz_core.run_grid` use this to keep publishing into
`results/viz_state.json` for the grind observer without waiting for the whole
batch.

## Already wired (Phase 1)

| Caller | Behavior |
|---|---|
| `score_probe.py` | One warm spawn for liquid10 × 2 windows × (strat+BH) |
| `corpus_score.py` | One warm spawn for available × 4 windows |
| `bull_score.py` | One warm spawn for all bull suites |
| `eval.py` `--matrix` / `run_matrix_mega` | **One** warm mega-batch (honesty×freq coalesce; freqs post-classify) |
| `eval.py` `eval_batch` / `--eval` | One warm spawn per slice (single cell / legacy) |
| `viz_core.run_grid` / `run_matrix_quick` | Dual / bulls / corpus / quick-matrix via warm batch + `publish_*` |

Untouched single-shot paths: `eval.py --check`, `--build-tapes`, `--eval` still
can call `run_gene` for one-offs; `--optimize` stays single-shot.

## Smoke check

```powershell
# tiny: 2 jobs (strategy + BH) on one tape
python -c "
from pathlib import Path
import sys
sys.path.insert(0, 'examples/flagship-musescript-module/harness')
from eval import stitch_source, buy_hold_source, run_gene_batch, DEFAULT_STRATEGY, FLAGSHIP
st = stitch_source(DEFAULT_STRATEGY)
bh = buy_hold_source()
tape = FLAGSHIP / 'tapes/eval_3m/SPY.csv'
print(run_gene_batch([
  {'id':'s','source':st,'tape':str(tape),'execution':'next-open','costBps':10},
  {'id':'b','source':bh,'tape':str(tape),'execution':'next-open','costBps':10},
]))
"
```

## Relation to the viz observer

The visualizer (`viz_server.py`) only **observes** `results/viz_state.json`.
Scoring agents/CLIs call `viz_core.publish_*` (or POST `/api/publish`). Warm
batch is plumbing under those scorers — pass/fail criteria and publish shape
are unchanged. Agents wiring bull/corpus/matrix publish should keep calling
`publish_*`; they automatically benefit once their loops go through
`run_gene_batch` / `run_grid`.

## Remaining checklist

- [x] Byte-identical regression: cold `run_gene` loop vs warm `run_gene_batch`
      on the top-9 meanrev corpus (diff sharpe/MDD/trades/pass) —
      `harness/batch_identity.py`, 2026-08-07: **540 strat + 60 BH cells exact match**
- [x] Time the 9 × meanrev corpus_score run — target **well under a minute**
      (was 9–18 min spawn overhead) — warm wall **1.49s** / 600 jobs; cold
      recheck of same grid **226s** (spawn tax)
- [x] Coalesce `cmd_matrix` into **one** mega-batch across honesty × freq slices
      — `run_matrix_mega` + `harness/batch_matrix_coalesce.py`: 6 slices / 18
      cells exact; legacy **6 spawns / 21.15s** → mega **1 spawn / 3.56s**
- [ ] Optional: wire `corpus_score` / `bull_score` CLI publish into viz_state
      (another agent may be doing this — extend, don't rewrite)
- [ ] Phase 2: `mederos --cli-tool=batch-eval` app-headless registry — **do not
      build** until a second/third tool wants the same convention

### Re-run identity / timing

```powershell
# full top-9 (cold ~4 min + warm ~2s)
python examples/flagship-musescript-module/harness/batch_identity.py
# warm timing only
python examples/flagship-musescript-module/harness/batch_identity.py --warm-only
# 6.1c matrix coalesce (legacy N spawns vs 1 mega)
python examples/flagship-musescript-module/harness/batch_matrix_coalesce.py
```

## Do not

- Change pass/fail criteria (`trades >= 1 and sharpe > 0 and d > 0 and mdd <= 0.25`)
- Edit flagship_v7g / v7h strategy DNA for this plumbing work
- Build Phase 2 Electron CLI tools yet
