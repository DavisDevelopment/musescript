# Engine matrix — op × engine honesty

Canonical **claims** for which ops run where, plus the **CI/local gate** that keeps those
claims honest. Source-of-truth eligibility tables:

| Surface | Eligibility | Doc |
|---------|-------------|-----|
| `muse.np` / packed vec | `WasmNpEligibility`, `VmNpEligibility` | [WASM_NP.md](WASM_NP.md) |
| `muse.pd` / frames | `WasmPdEligibility`, `VmPdEligibility` | [WASM_PD.md](WASM_PD.md) |
| Panel HostABI | `StrategyWasmEmitter.PANEL_HOST_ESCAPE` | README `muse` host section |
| Bytecode VM subset | `MuseBytecodeCompiler` + `TestBytecodeVmParity` | `SPEC_BYTECODE_VM.md` / `musescript/vm/README.md` |

Tags used below: **N** = claimed-native, **B** = builtin / stacked path, **H** = per-stmt
`host_eval`, **U** = unsupported / whole-module fallback. Fail closed — never silent BLAS.

## How to run

```powershell
# Windows
.\tools\engine_matrix.ps1
.\tools\engine_matrix.ps1 --list
.\tools\engine_matrix.ps1 --only ndarray,pd
.\tools\engine_matrix.ps1 --soak   # optional prefer-vm-soak only

# or directly
node tools/engine_matrix.mjs
```

```bash
# macOS / Linux / CI
bash tools/engine_matrix.sh
bash tools/engine_matrix.sh --list
bash tools/engine_matrix.sh --only ndarray,vm-parity
bash tools/engine_matrix.sh --soak
```

Requires: Haxe (see `.haxerc` / CI 4.3.6), `haxelib install utest hxnodejs`, Node 20+.
Any suite that fails build **or** run exits non-zero; suite names are printed before each
build and again in the final summary.

`.\run.ps1 engine-matrix` is an alias on Windows.

## Suites included (default matrix)

Manifest: [`tools/engine_matrix_suites.json`](../tools/engine_matrix_suites.json).

| Suite | Build | Runner | What it guards |
|-------|-------|--------|----------------|
| **ndarray** | `build-ndarray-tests.hxml` | `tests-ndarray.js` | NdArray + **`TestWasmNp`** (WASM NP native vs escape) |
| **host-evo** | `build-host-evo-followups.hxml` | `tests-host-evo-followups.js` | `muse.*`, panel WASM parity, NP/PD evo palette, panel/NMA fitness, hybrid WASM |
| **pd** | `build-pd-tests.hxml` | `tests-pd.js` | `muse.pd` M0–M4 + MultiIndex (F64/Str) + codes/factorize |
| **vm-parity** | `build-vm-parity.hxml` | `tests-vm-parity.js` | interp ↔ bytecode VM byte-identity (`TestBytecodeVmParity` / corpus) |
| **orderbook** | `build-orderbook-tests.hxml` | `tests-orderbook.js` | OrderBook groups / brackets |
| **portfolio** | `build-portfolio-tests.hxml` | `tests-portfolio.js` | portfolio / panel backtest surface |
| **muse-io** | `build-muse-io-tests.hxml` | `tests-muse-io.js` | `muse.re` / `fs` / `http` + ingest grants |

**Alternate (not default):** `build-muse-host-tests.hxml` — broader host suite (also re-runs
NdArray / `TestWasmNp` / LangClass). Default matrix uses focused **host-evo** + separate
**ndarray** so WASM NP is covered once.

## preferVm soak (optional regression gate)

`Fitness.preferVm` defaults **ON** (CorpusEvoRun `--no-vm` to opt out). The soak remains the
**Fitness-path** bit-drift regression harness (`evaluateVm` / `vmParityCheck` / `evaluate()` with
preferVm armed) in addition to the standing MuseVm corpus/evolved gate and cheap DetParityDump
VM tiers.

```powershell
# Full soak: DetParity (node↔golden) + vm-parity + Fitness preferVm soak
.\tools\prefer_vm_soak.ps1

# Faster: DetParity + Fitness soak only (skip full evolved MuseVm suite)
.\tools\prefer_vm_soak.ps1 -Quick

# Fitness suite only (engine-matrix --soak)
.\tools\prefer_vm_soak.ps1 -FitnessOnly
# or:  .\tools\engine_matrix.ps1 --soak
```

```bash
bash tools/prefer_vm_soak.sh
bash tools/prefer_vm_soak.sh --quick
bash tools/prefer_vm_soak.sh --fitness-only
# or:  bash tools/engine_matrix.sh --soak
```

| Piece | What |
|-------|------|
| DetParityDump | Node render ↔ `testdata/det-parity.golden.txt` (includes MuseVm `match=1` tiers) |
| **vm-parity** (unless `--quick`) | Existing corpus + evolved MuseVm interp↔VM (`TestVmParityCorpus`) |
| **prefer-vm-soak** | `TestPreferVmSoak`: preferVm default ON; corpus + evolved via `Fitness.vmParityCheck`; preferVm `evaluate()` route; DetParity match lines |

**CI posture:** job `prefer-vm-soak` in `pipeline-hardening.yml` runs on
`workflow_dispatch` + weekly schedule only (`continue-on-error: true`) — never on every
push/PR, never blocks required merge checks. Required jobs keep **vm-parity** inside
`hardening-tests` / `engine-matrix` (MuseVm direct; Fitness preferVm default ON).

## Op × engine snapshot (NP / PD)

Abbreviated from [WASM_NP.md](WASM_NP.md) / [WASM_PD.md](WASM_PD.md) — update those docs when
eligibility changes; this table is the navigator.

### `muse.np` (packed f64 / handle cliffs)

| Engine | Scalar mean/sum/dot of window | Vec create + mean/sum/get_flat | Axis+keepdims / reshape |
|--------|-------------------------------|--------------------------------|-------------------------|
| **Interp** | **N** | **N** | **N** |
| **JS** | **B** (`np_*`) | **B** | **B** |
| **Bytecode VM** | **B** (`VmNpEligibility`) | **H** create + **B** reduce (cliff 2; const 1-D ≤64) | **U** |
| **WASM** | **N** (≤64) | **N** packed `(base,len)` | **H** |
| **NMA** | Expand→interp (`nma-unsupported`) | — | — |

### `muse.pd` (opaque frames + packed rank + VM Series lane)

| Engine | Construct / select / groupby / … | `pd_rank1d` (≤64) | Series `pd_series`/`pd_shift`/`values` | `read_csv` / `read_parquet` |
|--------|----------------------------------|-------------------|----------------------------------------|----------------------------|
| **Interp** | **N** (Haxe) | **N** | **N** | **U** unless grant |
| **JS** | **B** (`pd_*`) | **B** | **B** | grant / Studio (parquet: Node + hyparquet) |
| **Bytecode VM** | **U** (frames/Index) | **H** OBJ `NdArrayF64` | **H** OBJ `Series`/`NdArrayF64` (`VmPdEligibility`) | **U** |
| **WASM** | **U** (opaque fallback) | **N** ≤64 | **U** (opaque Series) | **U** |
| **NMA** | Don't force frames into kind-switch | — | — | — |

## CI

GitHub Actions job **`engine-matrix`** in [`.github/workflows/pipeline-hardening.yml`](../.github/workflows/pipeline-hardening.yml)
runs `bash tools/engine_matrix.sh` on push/PR alongside the existing hardening / det-parity /
forecast / equity-digest jobs.

Optional **`prefer-vm-soak`** job (same workflow): manual / weekly, `continue-on-error`, not
required for merge. See § preferVm soak above.

## Files

| Path | Role |
|------|------|
| `tools/engine_matrix_suites.json` | Suite list (name, hxml, js, covers) + `optional` soak |
| `tools/engine_matrix.mjs` | Cross-platform runner (`--list` / `--only` / `--soak` / `--with-optional`) |
| `tools/engine_matrix.sh` / `.ps1` | Thin wrappers |
| `tools/prefer_vm_soak.sh` / `.ps1` | Full preferVm regression soak orchestrator |
| `build-prefer-vm-soak.hxml` | Fitness preferVm soak + TestDetParity |
| `docs/ENGINE_MATRIX.md` | This doc |
| `docs/WASM_NP.md` / `WASM_PD.md` | Per-op WASM/VM claims |
