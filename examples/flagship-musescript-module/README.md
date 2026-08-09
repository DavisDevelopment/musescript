# Flagship MuseScript Module

> **Collaborators:** this directory is **strategy research / experiment harness**, not the MuseScript
> language product and not a green CI gate. Product setup stays at the [repo README](../../README.md)
> and [CONTRIBUTING](../../CONTRIBUTING.md). Probe files under `strategies/probes/`, harness helpers
> named `_mk_*.py` / `_score_*.py`, and local `tapes/` / scoreboard JSON are scratch — do not
> promote a genome on corpus scoreboards alone (read the held-out sections below).

Iterate until staggering gains on **every** symbol-batch × window × honesty × trade-frequency cell.

**Current corpus champion:** `strategies/flagship_v7h.ms` — **liquid10 dual 20/20** + bulls **20/20** + corpus **60/60** + dBH_dual **~+1.585** (tip/Done seals).

> ### ⛔ v7h shows NO held-out improvement — "promote cleared" below is corpus-only
>
> v7h was promoted on dual/bulls/corpus/dBH before `heldout_gate.py` was ever run against it.
> On the frozen 54-symbol broad8mo set it has the **worst point estimates in the entire lineage**
> (10/54, mean d_sharpe −0.999, vs. baseline `flagship_ensemble_v1` at 13/54 / −0.709).
>
> **Stated precisely** (`harness/gate_stats.py`, 2026-08-07): paired against the baseline over the
> same 54 symbols the difference is **−0.291, 95% CI [−0.652, +0.064]** — *not* resolved. v7h is not
> demonstrably worse than v1 on this set. It is also **nowhere near demonstrably better**, which is
> the only thing that could justify a promotion. The honest verdict is `INDISTINGUISHABLE`, and an
> unresolved difference is not a pass.
>
> What *is* solid is the direction. Paired-vs-v1 deficits run perfectly monotonically with tuning
> round — v6l −0.069, v7 −0.110, v7b −0.131, v7c/d/e −0.196, v7f/g −0.247, v7h −0.291 — nine
> versions, no exceptions, while the tuned-corpus score climbed 48% → 100%. No single comparison
> carries that; the ordering does.
>
> Treat the scoreboard below as "fits the 15-symbol tuning set," never as "works." Full statistics:
> `harness/gate_stats.py`; full writeup: `results/BROAD8MO_REPORT.md`.

## Scoreboard (causal next-open, 10 bps)

| Cell | v6l | v7 | v7b | v7c | v7d | v7e | v7f | v7g | **v7h** |
|---|---|---|---|---|---|---|---|---|---|
| liquid10 × eval × any | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × any | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × 2022 × swing | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| liquid10 × eval × position | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | 10/10 | **10/10** |
| bulls liquid10 (2019+2024) | 4/20 | 6/20 | 8/20 | 11/20 | 14/20 | 15/20 | 16/20 | 17/20 | **20/20** |
| corpus available×4 | ~29/60 | ~29–31/60 | 35/60 (58.3%) | 38/60 (63.3%) | 41/60 (68.3%) | 42/60 (70.0%) | 43/60 (71.7%) | 44/60 (73.3%) | **60/60 (100%)** |
| quick matrix perfect | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | 10/12 | — |
| dual mean dBH | +1.49 | +1.55 | +1.63 | +1.60 | +1.58 | +1.58 | +1.58 | +1.58 | **+1.585** |

Promote: dual ≥18 + (bulls≥11 ∨ corpus≥55%) + dBH not >15% worse than DEFAULT v7g +1.58 (floor ~1.34) → corpus bar **CLEARED** via dual/bulls/corpus **20/20/60** + dBH +1.585 — **but the held-out gate REGRESSED, so this is not a promotion.** These four numbers are now known not to predict generalization; see the box above.

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

## Held-out v2 — multi-regime set (supersedes broad8mo for judging variants)

`broad8mo` is 54 symbols over ONE 8-month up-window. Measured: ~7 effective independent bets, and
**not one promote/reject decision in this thread's history is statistically resolvable on it**
(`harness/gate_stats.py`). It also cannot do CSCV over time — 166 bars with a 34-bar warmup has no
usable slices — so it is structurally blind to the overfitting it was built to catch.

`heldout_v2` fixes both. Built from the local `equities_daily.db` (1007 symbols, 2.6M bars):

| | folds | universe | purpose |
|---|---|---|---|
| **working** | 9 annual, 2014–2022 | 300 of 866 eligible | iterate + judge here |
| **sealed** | 2023-01-28 → 2026-08 | 101 | **touch once, on the final candidate** |

Working folds span real regime diversity — 2015 choppy, 2017 melt-up, 2018 two corrections,
2020 COVID crash + V, 2022 bear. The sealed set exploits a natural data boundary (the bulk fetch
stops 2023-01-27) so it is strictly *later in time* than every working fold.

```powershell
python examples/flagship-musescript-module/harness/build_heldout_v2.py --sealed  # deterministic rebuild
python examples/flagship-musescript-module/harness/heldout_v2.py --all-variants  # score + matrix
python examples/flagship-musescript-module/harness/heldout_v2.py --report        # inference
```

`tapes/` is gitignored; the builder is seeded, so the set is reconstructible from the script alone.

**First results (`results/HELDOUT_V2_REPORT.md`, 2026-08-07):** 116 of 117 variant×fold cells are
negative — every variant loses to buy-hold in every regime, including the 2022 bear and the 2020
crash. broad8mo's down/choppy edge **did not replicate**. v7b→v7h are identical to three decimals
across all nine folds: **seven rounds of tuning that took corpus 58%→100% produced no measurable
out-of-sample difference at all.** The one real effect is `flagship_ensemble_v4` (+0.294 paired vs
ensemble_v1, and **+0.229 at zero cost** — so it is signal, not just its 5.6-trades/symbol
turnover advantage). Note this reverses broad8mo, which rejected v4 at 4/54.

> ⚠ **Survivorship bias is real here.** The universe is names present in a recent fetch list,
> pulled retrospectively — companies that delisted or were acquired 2014–2022 are largely absent.
> Absolute returns are optimistic for everything, buy-hold most of all. **Only paired comparative
> claims are supported.** Do not quote an absolute return off this set.

## v7h DNA (tip / Done seals)

Prior v7g (QQQ deep-red sticky tip) plus quiet/sticky/ride hardening:

- **Tip/Done seals** across JPM/WMT/MSFT/SPY/AAPL/QQQ/AMD/GOOGL/NVDA + XOM mild-red / deep sticky; BAC sticky Done
- Soft-wall names (QQQ/AMD/GOOGL/NVDA @ 2019/2024) cleared on bulls + corpus

Rollback snapshot: `strategies/flagship_v7h_known_good.ms`. Prior champ file: `strategies/flagship_v7g.ms`.

## Grind visualizer (preferred for revisions & tests)

Rich local scoreboard UI that drives the same scoring logic as the harness CLIs (dual / bulls / corpus / matrix --quick), with live per-cell pass/fail + dBH, promote-bar meters, soft-wall highlights (QQQ/AMD/GOOGL/NVDA on 2019/2024), watch-mode re-score on `.ms` save, and side-by-side genome compare (v7d/e/f/g/h).

```powershell
# from repo root (gene-runner must exist — build once if needed)
haxe build-cli.hxml
python examples/flagship-musescript-module/harness/viz_server.py
# → http://127.0.0.1:8765/
```

**Workflow for v7i+:** open the viz → select candidate (or keep DEFAULT v7h as baseline) → enable **watch .ms → auto dual** while editing → use **Bulls / Corpus / Matrix / Full score** after meaningful DNA changes → **Score both** against v7h to confirm no dual/dBH regression. State persists to `results/viz_state.json`.

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
python examples/flagship-musescript-module/harness/score_probe.py strategies/flagship_v7h.ms
python examples/flagship-musescript-module/harness/eval.py --matrix --quick
python examples/flagship-musescript-module/harness/corpus_score.py strategies/flagship_v7h.ms
python examples/flagship-musescript-module/harness/bull_score.py strategies/flagship_v7h.ms
```

Warm batch details + remaining checklist: [`harness/BATCH_RUNNER.md`](harness/BATCH_RUNNER.md).

## Next war

1. Held-out / broad8mo generalization (do not promote on corpus alone)
2. Theoretical 12/12 needs swing floor loosen or IWM seed replace
3. Live / cost realism vs tape-tuned tip seals
