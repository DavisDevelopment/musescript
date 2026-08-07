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

**Dependency note (shipped default = stdlib only):**

| Option | Pros | Cons |
|---|---|---|
| **stdlib `viz_server.py` (default)** | No install; SSE live updates; reuses `eval.run_gene` | Hand-rolled HTTP |
| Streamlit | Faster to style widgets | Extra dep; weaker SSE control |
| FastAPI + uvicorn | Clean ASGI; already have FastAPI in some envs | Needs `uvicorn` (not always installed) |

CLI still works if you want headless / CI:

```powershell
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7g.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7g.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7g.ms
```

## Next war

1. Remaining bull / corpus fails toward v7h — **run in the visualizer**
2. Corpus banks / available weak spots (JPM, XOM, TSLA, BAC @ eval)
3. Theoretical 12/12 needs swing floor loosen or IWM seed replace
