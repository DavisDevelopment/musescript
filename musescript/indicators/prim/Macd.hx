package musescript.indicators.prim;

import musescript.indicators.MuseIndicator;
import musescript.indicators.prim.Ema;

/** MACD output: the three classic series at a given step (field names match `lib/MacdExt.hx`). */
typedef MacdOutput = {
	var macd:Float;
	var signal:Float;
	var histogram:Float;
}

/**
 * Moving Average Convergence Divergence — ported from wickra-core's
 * `MacdIndicator`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/macd.rs).
 *
 * MACD = EMA(fast) − EMA(slow), with a signal EMA on top. The signal EMA is
 * seeded from the first `signal` raw MACD values, so the first full
 * `MacdOutput` is emitted after `slow + signal − 1` inputs. A non-finite
 * input returns the last output without advancing any EMA. (Wickra's
 * bindings-only `batch_macd` fused fast path is deliberately not ported —
 * `IndicatorBatch.run` is the batch mechanism here and is bit-identical to
 * streaming by construction.)
 *
 * A `prim/` PRIMITIVE, not a builtin: MuseScript already exposes its own
 * `macd` builtin (deliberately NOT replaced, corpus/parity tests depend on
 * it). This faithful Wickra port exists as a reusable streaming building
 * block for `lib/` composites. See Ema.hx and ROADMAP.md epic 9.
 */
class Macd implements MuseIndicator<Float, MacdOutput> {
	public var fastPeriod(default, null):Int;
	public var slowPeriod(default, null):Int;
	public var signalPeriod(default, null):Int;
	var fast:Ema;
	var slow:Ema;
	var signalEma:Ema;
	var last:Null<MacdOutput>;

	public function new(fast:Int, slow:Int, signal:Int) {
		if (fast <= 0 || slow <= 0 || signal <= 0) throw "Macd: period must be > 0";
		if (fast >= slow) throw "Macd: fast period must be strictly less than slow period";
		fastPeriod = fast;
		slowPeriod = slow;
		signalPeriod = signal;
		this.fast = new Ema(fast);
		this.slow = new Ema(slow);
		signalEma = new Ema(signal);
		last = null;
	}

	/** Default `(12, 26, 9)` configuration, matching every classical chart package. */
	public static function classic():Macd return new Macd(12, 26, 9);

	public function update(input:Float):Null<MacdOutput> {
		if (!Math.isFinite(input)) return last;
		var f = fast.update(input);
		var s = slow.update(input);
		if (f == null || s == null) return null;
		var macd = f - s;
		var sig = signalEma.update(macd);
		if (sig == null) return null;
		var out:MacdOutput = { macd: macd, signal: sig, histogram: macd - sig };
		last = out;
		return out;
	}

	public function reset():Void {
		fast.reset();
		slow.reset();
		signalEma.reset();
		last = null;
	}

	// Slow EMA needs `slow` inputs to seed; signal EMA needs another `signal - 1`.
	public function warmupPeriod():Int return slowPeriod + signalPeriod - 1;

	public function isReady():Bool return last != null;
	public function name():String return "MACD";

	/** Most recent fully-computed output, or null before warmup — for composites reading state directly. */
	public function value():Null<MacdOutput> return last;
}
