# Flagship MuseScript Module

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current champion:** `strategies/flagship_v7g.ms` — **liquid10 dual 20/20** + bulls **17/20** + corpus **44/60** + dBH_dual **~+1.58** (promote cleared). Prior: `strategies/flagship_v7f.ms`.

## Scoreboard (causal next-open, 10 bps)

| Cell | v6l | v7 | v7b | v7c | v7d | v7e | v7f | **v7g** |
|---|---|---|---|---|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × eval × position | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| bulls liquid10 (2019+2024) | 4/20 | 6/20 | 8/20 | 11/20 | 14/20 | 15/20 | 16/20 | **17/20** |
| corpus available×4 | ~29/60 | ~29–31/60 | 35/60 (58.3%) | 38/60 (63.3%) | 41/60 (68.3%) | 42/60 (70.0%) | 43/60 (71.7%) | **44/60 (73.3%)** |
| quick matrix perfect | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | **10/12** |
| dual mean dBH | +1.49 | +1.55 | +1.63 | +1.60 | +1.58 | +1.58 | +1.58 | **+1.58** |

Promote: dual ≥18 + (bulls≥11 ∨ corpus≥55%) + dBH not >15% worse than DEFAULT v7f +1.58 (floor ~1.34) → **CLEARED** via bulls 17/20 + corpus 73.3% + dBH +1.58.

## ⚠️ Held-out gate — required before any future promotion

`results/BROAD8MO_REPORT.md` (2026-08-07): on a broad 54-symbol universe over the real last 8
months — not the tuned 15-symbol corpus above — **broad-universe performance degrades
MONOTONICALLY as the tuned-corpus score climbs, all the way through v7g.** v6l, the least-tuned
version in this whole lineage, generalizes best of all eight versions tested. Every promoted
"improvement" since has been tuning tighter to the validation set, not building a bigger real edge.

**Before calling anything a new champion, run:**
```powershell
python examples/flagship-musescript-module/harness/heldout_gate.py strategies/flagship_vNEW.ms
```
This scores the candidate against the frozen 54-symbol held-out set (`tapes/broad8mo/`) and
compares it to the frozen baseline (`results/broad8mo_baseline.json`, currently **v6l** — the
best-generalizing version found, not the current corpus champion) with a real pass/fail exit code.
A candidate that regresses vs. that baseline should not be promoted on the strength of the
corpus/bulls/dBH numbers above alone, no matter how good those look — that's exactly the pattern
that produced this whole gap. Full writeup, regime breakdown (this system's edge is real but
concentrated in down/choppy names, not trending ones), and the frozen-vs-refreshed-data tradeoff:
`results/BROAD8MO_REPORT.md`.

## v7g DNA (v7f + QQQ tip-lock)

Prior v7f (META/AMZN sticky bands + MSFT tip-lock + SPY deep-red tip + AAPL mild-red tip) plus:

- **QQQ@2019** series-time `qqqBar1Deep` crown suppress + deep-red sticky `tip>19%`

Rollback snapshot: `strategies/flagship_v7g_known_good.ms`. Prior champ file: `strategies/flagship_v7f.ms`.

## Grind visualizer (preferred for revisions & tests)

Rich local scoreboard UI that drives the same scoring logic as the harness CLIs (dual / bulls / corpus / matrix --quick), with live per-cell pass/fail + dBH, promote-bar meters, soft-wall highlights (QQQ/AMD/GOOGL/NVDA on 2019/2024), watch-mode re-score on `.ms` save, and side-by-side genome compare (v7d/e/f/g).

```powershell
# from repo root (gene-runner must exist — build once if needed)
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/viz_server.py
# → http://127.0.0.1:8765/
```

**Workflow for v7h+:** open the viz → select `flagship_v7h.ms` (or keep DEFAULT v7g as baseline) → enable **watch .ms → auto dual** while editing → use **Bulls / Corpus / Matrix / Full score** after meaningful DNA changes → **Score both** against v7g to confirm no dual/dBH regression. State persists to `results/viz_state.json`.

**CLIs that auto-publish** into `results/viz_state.json` (open viz_server to watch; publish is best-effort and never blocks scoring):

| CLI | Suite key | What lights up |
|---|---|---|
| `score_probe.py` | `dual` | liquid10 × eval_3m / wf_2022q1 cells mid-run |
| `bull_score.py` | `bulls` | liquid10 × bull windows (wf_2019q1 / wf_2024q4); champ/available remain console-only |
| `corpus_score.py` | `corpus` | available × 4 key windows |
| `eval.py --matrix` / `--matrix --quick` | `matrix` | batch×window×honesty×freq rows mid-run |

Grind agents can call the same hooks directly: `from viz_core import publish_job_start, publish_cell, publish_run, publish_job_done`.

**Dependency note (shipped default = stdlib only):**

| Option | Pros | Cons |
|---|---|---|
| **stdlib `viz_server.py` (default)** | No install; SSE live updates; reuses `eval.run_gene` | Hand-rolled HTTP |
| Streamlit | Faster to style widgets | Extra dep; weaker SSE control |
| FastAPI + uvicorn | Clean ASGI; already have FastAPI in some envs | Needs `uvicorn` (not always installed) |

CLI still works if you want headless / CI:

```powershell
haxe build-cli.hxml
haxe build-batch.hxml   # warm multi-tape runner (kills per-cell Node cold-start)
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7g.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7g.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7g.ms
```

Warm batch details + remaining checklist: [`harness/BATCH_RUNNER.md`](harness/BATCH_RUNNER.md).

## Next war

1. Remaining bull / corpus fails toward v7h — **run in the visualizer**
2. Corpus banks / available weak spots (JPM, XOM, TSLA, BAC @ eval)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
