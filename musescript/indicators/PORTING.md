# Porting Wickra indicators → MuseScript

The goal: port all of Wickra's indicator set
(github.com/wickra-lib/wickra, cloned read-only at `vendor/wickra/`) into
MuseScript's charting + strategy ecosystem, each as **one self-contained
streaming implementation** that is vectorized OR streamed from the same code
(ROADMAP.md epic 9). Status/inventory: `PORT_INVENTORY.txt`.

## The assembly line (why porting one indicator touches ONE file)

`IndicatorRegistryMacro` scans `lib/` at compile time and collects every
class's `spec()` into the registry. `WickraBuiltins.install`, `BuiltinSigs`,
and `JsBackend` dispatch **all derive from that registry** — so adding an
indicator never edits a shared list. Drop a file in `lib/`, rebuild, done.
This is what makes many people (or agents) porting in parallel conflict-free:
no two ports ever touch the same file.

## Where a port goes

- **`lib/Foo.hx`** — a genuinely-new indicator → becomes a builtin. Tier 1 in
  the inventory.
- **`prim/Foo.hx`** — a name that COLLIDES with an existing MuseScript builtin
  (ema, sma, rsi, atr, macd, wma, mom, roc, vwap, max_drawdown). Ported as a
  reusable streaming primitive for composites to build on; **not** registered
  as a builtin (would overwrite the existing one). No `spec()`.
- **DO NOT port (yet)**: Tier 3 in the inventory — inputs are
  `DerivativesTick`/`CrossSection`/`Trade`/`OrderBook`/`TradeQuote`, which the
  MuseScript `Bar` model doesn't carry. These need new data feeds first.

## The recipe for one indicator

1. **Read the Rust source**: `vendor/wickra/crates/wickra-core/src/indicators/<name>.rs`.
   Note its `type Input` (Candle / f64 / (f64,f64)), `type Output` (f64 or a
   struct), constructor params, and the `update`/`reset` bodies.
2. **Translate line-for-line** into `lib/<PascalName>.hx` implementing
   `MuseIndicator<TIn, TOut>` (`update`/`reset`/`warmupPeriod`/`isReady`/`name`).
   `Option<T>` → `Null<T>`;    rolling windows → `RingBuffer` (or `FloatSeries` /
   `GrowableVec` for absolute-index series) — **not** `Array` + `shift` / `for..in`
   on hot paths (see `RingBuffer.hx` and `evo/nma/JIT_AUTHORING_GUIDE.md`).
   `.shift()` in `lib/` is a **build/CI fail** (OPEN_ITEMS 1.2: macro + `TestIndicatorLibHygiene`
   + `tools/ban_indicator_shift.mjs`); `unshift` is still allowed.
   Struct output → a typedef (see `lib/Aroon.hx`'s `AroonOutput`). Cite the
   source path in the class doc comment. If it composes a primitive
   (`Ema::new`, `Rsi::new`, ...), use the `prim/` version; port that primitive
   first if it's missing. Shared swing detection → `geom.SwingGraph`, not a
   shared `SwingGraph` (no private `SwingTracker` / `Array.shift`).
3. **Add `static function spec():IndicatorSpec`** — pick the input helper
   matching `type Input`:
   - Candle → `IndicatorCache.evalBar(...)` (args typically `[TWindow]`).
   - f64 → `IndicatorCache.evalSeries(...)` (args `[TSeries, TWindow]`; first
     arg is the price series, default `"close"`).
   - (f64,f64) → `IndicatorCache.evalPair(...)` (args `[TSeries, TSeries, ...]`).
   `nanFill` is `Math.NaN` for scalar output, a NaN-filled struct for
   multi-output. Key the cache on name + all params so distinct callsites
   don't share state.
4. **Write tests** in `musescript/tests/ports/TestPort<Batch>.hx` (package
   `musescript.tests.ports`, class extends `utest.Test`). Per indicator:
   - **Known-value cases transcribed from the Rust `#[cfg(test)]` fixtures** —
     the same reference numbers upstream checks itself against, NOT re-derived.
   - **`batch_equals_streaming`** — Wickra's own name for the property that
     `IndicatorBatch.run(a, xs)` equals `[for (x in xs) b.update(x)]`.
   The file is auto-registered by `PortTestsMacro` (scans `tests/ports/`), so
   there is **no edit to TestMain.hx** — every shared file in the port
   workflow is now macro-collected, making parallel porting fully
   conflict-free (each batch touches only its own new files).

## Hard gates (every port must pass)

- `haxe build.hxml` clean, then `node build/js/tests.js` → 0 failures.
- `TestIndicatorPorts.testEveryRegisteredIndicatorIsCallable` — the generic
  net that drives EVERY registered indicator through a real interp backtest;
  a mis-wired port (bad dispatch, arg mishandling, crash) fails here for free.
- `batch_equals_streaming` for the ported indicator.
- Known-value parity with the Rust fixture.

## Verify by running, not by "done"

A port isn't done because the file compiles — run the suite and see the new
tests pass. Backend "done" ≠ run.
