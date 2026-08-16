# Contributing to MuseScript

Companion to the main [README](README.md). Keep that file for language/API reference; this file is
how to work in the tree without stepping on landmines.

## Setup (minimum)

```powershell
# From this repo root
haxelib install utest
haxelib install hxnodejs
haxelib dev musescript .
.\run.ps1 venv          # .venv + requirements.txt
.\run.ps1 test          # Node utest suite
```

Optional but common: `.\run.ps1 engine-matrix` (honesty gate — see [docs/ENGINE_MATRIX.md](docs/ENGINE_MATRIX.md)).

Haxe version is pinned in `.haxerc` (currently **5.0.0-preview.1**). Mismatch = mysterious builds.

## Branches & PRs

- Default branch: **`main`**.
- Prefer small, reviewable PRs with a clear “why” (language fix vs evo perf vs docs).
- CI: `.github/workflows/pipeline-hardening.yml` (includes engine-matrix). Local green before push
  when the change touches emitters, builtins, fitness, or WASM.
- Do **not** force-push `main`. Do not `--no-verify` hooks unless the owner asks.

If you are working from the Mederos monorepo submodule checkout, confirm `git remote -v` and that
commits land in **this** repo (`MederosDigital/musescript`), not accidentally only in the parent.

## Conventions

- **Honesty over cosmetics.** Naked Sharpe claims, silent fallbacks, and “best of N without deflation”
  get rejected. Prefer the engine matrix / gene-runner honesty paths.
- Prefer existing patterns in `musescript/` (Haxe) and `tools/` (Python/Node) over new top-level
  frameworks.
- Language surface docs live in the README; deeper op×engine claims live under `docs/`.
- Generated artifacts: rebuild, don’t hand-edit (`build/js`, `build/py`, `build/wasm`, grpc stubs
  under `graal/src/main/python/*_pb2*.py`).

## Docs: source of truth vs scratch

| Source of truth | Scratch / triage |
|-----------------|------------------|
| `README.md`, `docs/*.md`, this file | `OPEN_ITEMS.md` (aggregated backlog; useful, not a contract) |
| Package READMEs in sibling `../musegene`, `../musescript-kestrel` | Muse-lab root `*_PLAN.md` / `*_HANDOFF.md` |
| Flagship honesty rules in `examples/flagship-musescript-module/README.md` | `strategies/probes/`, harness `_mk_*.py` / `_score_*.py` |

## Landmines (do not commit / do not “clean up” casually)

| Path / pattern | Why |
|----------------|-----|
| `build/`, `dump/`, `node_modules/`, `.venv/` | Generated or local |
| `corpus/pine-organic/` | Third-party clones; regenerable; mixed licenses |
| `vendor/` | Local vendor trees |
| `musescript/murmuration/` | Proprietary simulator — gitignored from the open repo |
| `build-kestrel*.hxml`, `build-*murmuration*.hxml` | Private classpath build configs — gitignored |
| `../musescript-kestrel/` | Proprietary sibling package; not part of the open publish |
| Flagship `tapes/`, large `results/*.json` dumps | Data / experiment outputs; often gitignored |
| Secrets / API keys anywhere | Never |

Public CLI build: `haxe build-cli.hxml` → `build/js/gene-runner.js`. Kestrel-wired builds are
out-of-tree / private (`build-kestrel*.hxml`) and must not be required for open-repo green.

## Sibling packages

- **MuseGene** (`../musegene`): Python GP; needs `gene-runner.js` built once.
- **Kestrel** (`../musescript-kestrel`): proprietary; register via `KestrelBootstrap` under `#if kestrel`.
- **Risk-clause audit** (`../mw-risk-clause-audit`): separate checkout/branch for evo RCA — don’t
  confuse it with day-to-day `main` language work.

## Tests worth knowing

| Command | What |
|---------|------|
| `.\run.ps1 test` | Main Node suite |
| `.\run.ps1 test-py` | Python host suite |
| `.\run.ps1 07` | Cross-runtime numeric stress |
| `.\run.ps1 engine-matrix` | Op×engine honesty gate (preflight: `.shift()` ban in `indicators/lib/`) |
| `node tools/ban_indicator_shift.mjs` | OPEN_ITEMS 1.2 grep: no `.shift()` in `musescript/indicators/lib/` |
| `.\run.ps1 all` | Examples + both test suites |

Flagship strategy research is **not** the unit-test gate. See the flagship module README before
tuning `.ms` genomes or trusting corpus scoreboards.
