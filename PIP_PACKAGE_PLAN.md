# pip package plan — MuseScript's Python target

> **SUPERSEDED FOR NOW (2026-07-25):** the near-term npm/pip priority is packaging the
> **desktop tools** (the Electron app + the local relay/dataserver node), not the MuseScript
> language toolchain — see `kalshi-ai-advisor/PIP_PACKAGE_PLAN.md` for that plan. This document
> describes a real, separate, legitimate future project (a pip-installable MuseScript math-kernel
> compiler for Python quant users), just not the current priority. Keep it; don't execute it
> ahead of the desktop-tools package without checking in first.

**Audience:** whoever picks this up next (Cursor or otherwise) to actually build it out.
**Status as of 2026-07-25 (verified, not assumed):**

- ❌ **No pip package, no `pyproject.toml`, no `setup.py` exists anywhere in the repo.** Confirmed
  empty at `kalshi-ai-advisor/`, `mobile/`, and `muse-lab/`. Every Python-packaging-looking hit under
  `muse-lab` is inside a `venv/`/`site-packages/` (third-party, not this project) or vendored code.
  `pip install musescript` (or any name) gets nothing today.
- ✅ **The underlying Python compile target is real, not vaporware** — `PyEmitter.hx` +
  `NumbaBackend.hx` exist, `build-py.hxml` compiles a real `utest` suite plus example programs to
  `build/py/*.py`, and the README documents running them (`.\run.ps1 test-py`, `.\run.ps1 07`).
- ⚠️ **Critical scoping fact, read the README's own words before promising anything wider**: the
  Python/numba target is documented under **"Math-only compilation"** — it only accepts "pure
  numeric `function` decls (no bars/orders/match/yield)". It is a kernel compiler
  (`MuseScript.compileMath(src, "polySum", { target: "numba" })`), **not** a full strategy execution
  backend. There is no evidence anywhere that a full `strategy { onBar { ... } }` program with
  orders/state runs end-to-end as emitted Python — only the JS/interp/WASM tiers do that (see
  `MuseRuntime.run` in `runtime/MuseRuntime.hx`, which only offers `"interp"`/`"js"`/`"wasm"` tiers,
  notably **not** `"python"`).
- **Consequence for marketing copy**: mederos-web's homepage currently says MuseScript "compiles to
  JavaScript, Python, numba-JIT, and native WebAssembly" in one breath, implying parity across all
  four for full strategies. That's accurate for math kernels, not for strategies. **Before shipping
  a pip package (or leaving that homepage line as-is), decide whether to (a) scope the pip package
  honestly to math-kernel compilation only, matching what actually exists, or (b) build out full
  strategy execution in Python first and then ship the pip package** — don't let the package's
  existence imply more than the README already scopes.

## Decide first: what does `pip install musescript` actually give someone?

Given the scoping fact above, two honest options:

**A. A math-kernel compiler package** (matches reality today): `pip install musescript` gives a
   Python function `compile_math(source, fn_name, target="numba")` that JIT-compiles a MuseScript
   numeric function into a callable Python/numba function. Useful for someone who wants MuseScript's
   indicator-kernel math (SMA/EMA/RSI/ATR-style functions — see `examples/09-indicator-kernels`) fast
   inside an existing Python quant stack, without wanting the whole strategy DSL.

**B. A full strategy runtime for Python** (does not exist yet): would require either (i) extending
   `PyEmitter` to cover the full `on_bar`/order/harness surface the JS/interp/WASM tiers already
   have, which is a real language-backend engineering project, not a packaging task — or (ii) a
   Python package that embeds/calls the existing JS runtime (via a bundled Node subprocess, or a
   WASM-in-Python route like `wasmtime-py`), trading "full strategy support" for "not really native
   Python."

**Recommendation: ship A now, explicitly scoped as a math-kernel compiler, and treat B as a separate,
much larger project** (arguably: finish it before promising it anywhere, including in this repo's
own README wording, which should probably be tightened alongside this work to avoid overclaiming).

## Phase 1 — Package skeleton (for option A)

1. New `muse-lab/muse-script/pip/` (or a sibling directory) containing:
   - `pyproject.toml` (PEP 621 metadata, `build-backend = "setuptools.build_meta"` or `hatchling` —
     either is fine for a package with no compiled-C-extension of its own).
   - A thin Python wrapper module (`musescript/__init__.py`) exposing `compile_math(...)` and
     `run_kernel(...)`-style functions.
   - The actual code generation still runs through the Haxe `PyEmitter` — decide whether the pip
     package **ships pre-generated `.py` output for a fixed kernel library** (simplest, matches how
     the indicator-kernel examples already work) or **shells out to a bundled Haxe-compiled
     dispatcher** at import time (more flexible, more moving parts, needs the Haxe toolchain or a
     pre-built artifact bundled in the wheel).
2. Confirm `musescript` is free on PyPI — **check independently of the npm name-availability check**,
   PyPI and npm are different registries with different squatting histories.
3. `numba` as an optional dependency (`pip install musescript[numba]`) rather than a hard requirement
   — the plain-Python emission path (`PyEmitter` without `@njit`) should work with zero extra deps for
   users who don't want the numba install weight/compile-on-first-call latency.

## Phase 2 — Test the package the way a consumer would

1. Reuse the existing `build-py.hxml` test suite's known-good outputs as golden values — the Python
   emitter is already tested via Haxe's own `utest`/`run.ps1 test-py`; the pip package's job is to
   package that output faithfully, not to re-derive correctness. A packaging bug that silently
   changes numeric output would be worse than no package at all.
2. `pip install .` into a scratch venv, run a kernel from the indicator-kernel example set
   (SMA/EMA/RSI/ATR — `examples/09-indicator-kernels`), diff against the known Haxe-side reference
   values.
3. Test on a machine without numba installed too — confirm the plain-Python path degrades cleanly
   rather than throwing on import.

## Phase 3 — CI publish pipeline

1. GitHub Actions workflow on version tag: pin Haxe version (5.0.0-preview.1, same pinning caution as
   the npm plan — this is a preview toolchain release), run the Haxe→Python codegen step, build the
   wheel + sdist (`python -m build`), `twine upload` with a `PYPI_API_TOKEN` secret (or trusted
   publishing via OIDC, which avoids needing a long-lived token at all — prefer this if the CI
   platform supports it).
2. Version the pip package independently of (but linked to) the Haxe project's own version — document
   the mapping (e.g. pip `0.1.x` tracks musescript language version `X`) so a bug report against the
   pip package can be traced back to the right Haxe commit.

## Open questions

- Confirm `musescript` availability on PyPI; have a fallback name ready (`musescript-math`,
  `musescript-kernels` — arguably a more honest name given the actual scope in option A).
- Decide, with the rest of the team, whether the homepage's "compiles to ... Python, numba-JIT"
  phrasing should be tightened to "math-kernel compilation to Python/numba" before or alongside this
  package shipping — right now the marketing claim and the actual capability are misaligned, and this
  package is the moment to either close that gap (ship B) or correct the claim (ship A + fix copy).
- If option B is ever pursued: this is real backend engineering (new PyEmitter coverage for
  bars/orders/state), not something to scope inside a "packaging plan" — flag it as its own project
  with its own design doc if it's picked up.
