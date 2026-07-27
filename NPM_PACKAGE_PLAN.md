# npm package plan — MuseScript CLI + runtime

> **SUPERSEDED FOR NOW (2026-07-25):** the near-term npm/pip priority is packaging the
> **desktop tools** (the Electron app + the local relay/dataserver node), not the MuseScript
> language toolchain — see `kalshai/mobile/NPM_PACKAGE_PLAN.md` for that plan. This document
> describes a real, separate, legitimate future project (an npm-installable MuseScript
> compiler/runtime for JS developers), just not the current priority. Keep it; don't execute
> it ahead of the desktop-tools packages without checking in first.

**Audience:** whoever picks this up next (Cursor or otherwise) to actually build it out.
**Status as of 2026-07-25 (verified, not assumed):**

- ❌ **No npm package exists.** `muse-lab/muse-script/` is a Haxe/haxelib project (`haxelib.json`,
  name `musescript`, for `haxelib install`) with **no root `package.json`, no `bin` entry, no
  `.npmignore`**. `README.md` targets Haxe developers directly (requires installing Haxe 5.0
  preview + haxelib deps).
- ❌ `npm install musescript` today either fails or (worse) installs an unrelated package of that
  name if one happens to exist on the registry — **verify name availability on npmjs.com before
  committing to it anywhere in marketing copy.**
- ✅ What *does* exist and already works, compiled to plain JS, no Haxe toolchain needed at runtime:
  - `build/js/muse-runtime.js` — `@:expose("MuseRuntime")`, pure JS, no Sys/node deps. Exposes
    `.run(source, bars, opts)`, `.runPanel(...)`, `.emitWat(...)`, `.check(...)`. This is the browser
    runtime already embedded on mederos-web (`/engine`, `/convert`'s backtest button).
  - `build/js/pine2muse-web.js` — `@:expose("PineConvert")`, same deal, `.convert(src)`.
  - `musescript.cli.GeneRunner` and `musescript.pinescript.cli.Pine2Muse` — Haxe `-main` classes
    compiled to Node-targeting JS (`build/js/gene-runner.js`, `build/js/pine2muse.js`) that use
    `Sys`/file I/O — these are the CLI-shaped pieces, currently only reachable by running
    `node build/js/<name>.js` directly after a manual `haxe <hxml>` build.
- **Verdict: the runtime exists and is genuinely solid (parity-gated, tested). The packaging layer
  — the actual `npm publish`-able artifact — does not exist at all.** This is closer to "build the
  box" than "fix the contents."

## Decide first: what does `npm install musescript` actually give someone?

Pick one (or both, as separate packages) before writing any packaging code:

**A. A CLI** (`npx musescript convert strategy.pine`, `musescript run strategy.ms --tape data.csv`)
   — wraps `Pine2Muse`/`GeneRunner`'s logic, meant for a developer's terminal/CI pipeline.

**B. A library** (`import { run, convert } from "musescript"` in a Node or bundler project) — wraps
   `muse-runtime.js`/`pine2muse-web.js` as an importable module with real TypeScript types, meant for
   someone embedding MuseScript execution inside their own app (this is literally what
   `mederos-web/src/lib/museEngine.ts` already does today, just via a raw `<script>` tag instead of
   an npm import).

Recommendation: **ship B first** — it's almost entirely packaging work over something that already
runs correctly (the exact same file mederos-web already serves), versus A which needs the CLI mains
hardened for arbitrary user input, `--help` text, exit codes, etc. B is the shorter path to a real,
non-embarrassing `npm install` command.

## Phase 1 — Package skeleton

1. New `muse-lab/muse-script/npm/` subdirectory (keep it out of the Haxe project root so `haxelib`
   consumers aren't affected) — or a sibling package at the monorepo root; pick based on how the repo
   is meant to publish (single package vs. workspace).
2. `package.json`:
   - `name`: confirm `musescript` is free on npm; if not, candidates: `@mederos/musescript`,
     `musescript-lang`, `musescript-runtime`.
   - `main`/`module`/`types` fields for CJS + ESM + `.d.ts` — Haxe's JS output is plain ES5/ES6 by
     default (`-D js_es=6` is already used per `extraParams.hxml`), so wrapping it for dual
     CJS/ESM consumption is mostly a matter of a thin index shim, not touching the Haxe output.
   - `bin` field if shipping the CLI (Phase A above).
   - `files` allowlist (or `.npmignore`) so only the built JS + types + README ship, never Haxe
     source, `build/graal`, `corpus/`, etc. — this repo has a LOT of non-shippable build artifacts
     (JVM jars, corpus data) that must never end up in the npm tarball.
3. A `prepublishOnly` (or CI-driven) build step that runs the actual `haxe build-runtime.hxml` /
   `haxe build-pine-web.hxml` and copies the output into the package's `dist/`, so publishing never
   ships stale JS — this exact staleness bug already bit the `/engine` demo widget once this session
   (see [[live-demo-widget-embed-2026-07]]) and will recur here if the build step is skipped.

## Phase 2 — TypeScript types

`museEngine.ts` in `mederos-web/src/lib/` already hand-wrote the full type surface
(`PineConvertResult`, `MuseRunResult`, `MuseRunOpts`, `Bar`, etc.) against the real runtime — **reuse
those types verbatim as the package's `.d.ts`**, don't re-derive them from scratch. That file is the
single best source of truth for what the JS API actually returns, since it was written by testing
the real runtime's real output shapes.

## Phase 3 — Test the package the way a consumer would

1. `npm pack` locally, install the resulting tarball into a scratch project (`npm install
   /path/to/musescript-0.1.0.tgz`), and actually `require`/`import` it — don't trust `npm publish
   --dry-run` alone.
2. Verify both a plain Node `require(...)` and a bundler-based `import ... from "musescript"` path
   (Vite/webpack) resolve correctly — ESM/CJS dual-package hazard is the single most common npm
   packaging bug.
3. Confirm `MuseRuntime.run(...)` executes end-to-end from the packaged build with a trivial
   strategy + synthetic bars, matching known output (reuse a case from
   `musescript/pinescript/tests/PineParityHarness.hx`'s expected numbers as a golden check).

## Phase 4 — CI publish pipeline

1. GitHub Actions workflow triggered on version tag: `haxe` toolchain setup (pin the exact Haxe
   version — 5.0.0-preview.1 per the README, note this is a *preview* build and pinning matters more
   than usual), run the build step from Phase 1, `npm publish` with `NPM_TOKEN` secret.
2. Enable npm provenance (`--provenance` flag, needs OIDC-enabled Actions) — free, and increasingly
   expected for supply-chain trust; cheap credibility win consistent with the project's whole "show
   the receipts" posture.
3. Semantic versioning discipline: since this wraps a fast-moving Haxe codebase, decide a policy for
   when the npm version bumps relative to internal changes (every merge to the exposed surface? a
   manual release cadence?) before the first publish, not after.

## Open questions

- Confirm package name availability on npmjs.com.
- Decide: one package (runtime + CLI together) or split (`musescript` for the library,
  `musescript-cli` for the CLI) — splitting keeps the library's dependency footprint minimal for
  consumers who only want to `import` it into a bundle.
- `wabt-*.js` (WASM assembler, ~800KB per the demo widget build) is a real dependency of the WASM
  tier — decide whether it ships bundled (simple, larger package) or as a lazy-loaded optional chunk
  (smaller default install, one extra async step for WASM users).
