package musescript.indicators;

/**
 * One indicator's streaming state — the "single implementation, vectorized
 * OR streamed" mechanism (ROADMAP.md). Modeled directly on Wickra's
 * `Indicator` trait (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/traits.rs):
 * `update` is the ONLY computation entry point (O(1) amortized — no replays
 * over history), batch/vectorized mode is free via `IndicatorBatch.run`
 * rather than a second hand-written implementation, and every indicator
 * ships a `batch_equals_streaming` test (see TestIndicatorPorts.hx) proving
 * the two modes can never silently diverge.
 *
 * Differs from Wickra's trait in exactly the ways Haxe/MuseScript's own
 * constraints require: `Null<TOut>` instead of `Option<TOut>` for warmup
 * (same semantics — null until `warmupPeriod()` inputs have been consumed,
 * non-null after), and no `Copy` bound on `TIn` (Haxe has no such concept).
 *
 * Scope note: this interface — and the indicators implementing it in this
 * package — covers the shared interp/JS layer only (MuseScript's "JS tier"
 * already compiles these exact same Haxe functions, not a separate
 * hand-written JS implementation). The WASM tier is NOT wired to these yet;
 * an unported indicator called from a WASM-emitted strategy behaves exactly
 * like any other unsupported construct today (graceful fallback to interp/js
 * — see StrategyWasmEmitter's EmitUnsupported path). Porting a hot indicator
 * to WAT is a separate, per-indicator follow-up, prioritized by actual
 * profiled need — not attempted upfront for all 514 (ROADMAP.md epic 9).
 */
interface MuseIndicator<TIn, TOut> {
	/** Feed one new input; returns null during warmup, the computed value after. */
	function update(input:TIn):Null<TOut>;

	/** Return to the state of a freshly-constructed instance. */
	function reset():Void;

	/** How many `update()` calls before the first non-null output. */
	function warmupPeriod():Int;

	/** True once `update()` has returned a non-null value at least once since the last reset. */
	function isReady():Bool;

	/** Stable indicator name, for logging/diagnostics — not the MuseScript builtin name. */
	function name():String;
}
