# SPEC — warm batch-eval runner (kills the per-cell Node cold-start tax)

**Status:** Design spec for Cursor, 2026-08-07. Diagnosed live tonight while running the
`flagship-musescript-module` example harness against a new 28-strategy mean-reversion library
(`examples/flagship-musescript-module/strategies/meanrev/*.ms`). Phase 1 is a scoped, buildable
unblock; Phase 2 is architectural direction, not a same-night ask.

## The problem, measured, not guessed

`examples/flagship-musescript-module/harness/eval.py`'s `run_gene_raw()` shells out to Node **once
per single backtest**:

```python
cmd = ["node", str(RUNNER), "--source", str(src_path), "--target", "js", "--seed", str(seed), ...]
subprocess.run(cmd, ...)
```

`score_probe.py`, `corpus_score.py`, `bull_score.py`, and `eval.py --matrix` all call this in a loop
— once per strategy, per symbol, per window, **plus a second call for the buy-hold baseline every
single time**, even though the buy-hold source is byte-identical across every cell of every run.

Timed tonight, cold:

```
$ time node build/js/gene-runner.js --source <file> --target js --check
real  0m0.527s
```

That's a **parse-only `--check`**, before a tape is even loaded. `build/js/gene-runner.js` is a
4.16 MB bundle — the ~0.5s is Node process startup + V8 parsing/compiling that bundle from cold,
paid again on every single invocation. A `corpus_score.py` run against 9 strategies × 15 symbols ×
4 windows × 2 (strategy + BH) is ~1,080 process spawns — **9-18 minutes of pure spawn overhead**,
not backtest compute. The compiled runtime itself is not slow (prior benchmarks put warm/in-process
execution at 720k-1.4M bars/s — see `musescript-perf-optimization` history); this is 100% a harness
architecture cost, not a regression anywhere in the actual engine.

## Phase 1 — a warm batch-runner (build this now)

**Goal:** collapse N spawns into 1 for any batch of backtests, with zero change to what gets
measured (same execution semantics, same cost model, same output shape per cell — this is a
plumbing change, not a scoring change).

### New entry point: `build/js/batch-runner.js`

A new Node script (or a `--batch` mode bolted onto `gene-runner.js` if that's a smaller diff —
Cursor's call which is cleaner given the existing file's structure) that:

1. Reads a **job manifest** — NDJSON on stdin, one job per line:
   ```json
   {"id": "spy-eval3m", "source": "<full stitched .ms source>", "tape": "path/to/SPY.csv", "execution": "next-open", "costBps": 10, "seed": 42}
   ```
2. **Caches compiled strategies by source hash.** The buy-hold source is identical across every job
   in a batch — compile it exactly once. Any strategy re-tested across multiple symbols/windows in
   the same batch (which is the common case) also compiles once.
3. **Caches parsed tapes by path.** Re-reading/re-parsing the same CSV for every job that touches it
   is pure waste inside one process lifetime.
4. Runs each job against the already-warm interpreter/VM, and **streams one NDJSON result line to
   stdout as each job completes** (not buffered until the end — a caller grading hundreds of cells
   wants to see progress, and a crash partway through shouldn't lose completed results):
   ```json
   {"id": "spy-eval3m", "ok": true, "sharpe": 0.42, "maxDrawdown": 0.11, "trades": 4, "winRate": 0.5, "finalEquity": 103200}
   ```
5. Exits 0 once the manifest is exhausted, non-zero on a fatal (non-per-job) error.

Keep the existing single-shot `gene-runner.js --source ... --optimize ...` CLI working unchanged —
this is additive. Interactive single-strategy iteration (the common case while hand-tuning one
strategy) doesn't need batching; grading a whole library does.

### Python side: `eval.py` gets a batch path

Add `run_gene_batch(jobs: list[dict]) -> dict[str, Metrics]` to `eval.py`:
- Builds the NDJSON manifest (reusing `stitch_source` per distinct strategy file, and the existing
  `BH` constant for every buy-hold job — so the manifest itself already de-dupes at the Python
  level before the Node side de-dupes again by hash).
- Spawns `batch-runner.js` **once**, writes the manifest to its stdin, reads NDJSON results off
  stdout as they arrive.
- Returns a `{job_id: Metrics}` dict, same `Metrics` dataclass `run_gene` already returns today —
  callers shouldn't need to know or care that batching happened underneath.

Then rewrite `score_probe.py`, `corpus_score.py`, `bull_score.py`, and `eval.py`'s `--matrix` path
to build one job list per run and call `run_gene_batch` once, instead of looping `run_gene` calls.
**Don't change the pass/fail criteria anywhere** (`m.trades >= 1 and m.sharpe > 0 and d > 0 and
m.max_drawdown <= 0.25`) — this spec is about wall-clock, not about changing what "robust" means.

### Acceptance criteria

- `corpus_score.py` against the 9 strongest `strategies/meanrev/*.ms` candidates (see
  `strategies/meanrev/README.md` once it exists) finishes in well under a minute, not
  9-18 minutes, with **byte-identical per-cell results** to the current one-spawn-per-cell path (run
  both, diff the pass/fail + sharpe/drawdown/trades numbers — this is the actual regression test,
  not a vibe check).
- `score_probe.py` on a single strategy still works standalone (doesn't require batch mode for the
  1-strategy case — no forced ceremony for quick interactive checks).
- Existing `eval.py --check`, `--build-tapes`, `--eval`, `--optimize` single-shot paths are
  untouched.

## Phase 2 — special CLI paths in the shipped app (design-toward, not tonight)

Longer-term direction, not scoped for immediate build: today every one-off capability like this
(and there will be more — `eval.py --matrix`, `bull_score.py`, the various `harness/_*.py` probe
scripts, this new batch-runner) lives as a bespoke script only reachable by someone who knows the
exact `python examples/.../harness/whatever.py` incantation. The shipped app (`mobile/`, via
Electron on desktop) already bundles the compiled MuseScript runtime and a Python bridge for other
purposes — the idea is to stop re-wiring engine access from scratch in every new script and instead
give the app's own entry point a documented, discoverable "headless tool mode":

```
mederos --cli-tool=batch-eval --manifest=path/to/jobs.ndjson
```

Sketch (not a commitment to this exact shape — Cursor should propose the real design once Phase 1
exists and there's a second or third tool to generalize from, so the convention is grounded in
actual needs rather than guessed up front):
- `electron/main.cjs` checks `process.argv` **before** any window/GUI bootstrap. A recognized
  `--cli-tool=<name>` flag short-circuits straight to that tool's logic, prints results, and calls
  `app.exit(code)` — no window ever created.
- Each tool is a small registry entry (name → handler function), so adding the next one-off
  capability means registering a handler, not inventing a new bespoke script + a new manual
  invocation ritual that only the person who wrote it remembers.
- This buys: one bundled runtime shared by every tool (no duplicate engine-wiring code), one
  discoverable `--help`-able surface, and a natural place for future tools (batch grading, corpus
  sweeps, whatever comes next) to live instead of accreting in `harness/` forever.

**Do not build Phase 2 speculatively.** Land Phase 1, use it for real (starting with grading the
mean-reversion library), and let the second or third tool that wants this convention tell you what
the registry/dispatch shape actually needs to be — that's a much better spec input than guessing
it now.
