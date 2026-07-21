package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Zero-Lag MACD output: the MACD line, its signal line, and the histogram. */
typedef ZeroLagMacdOutput = {
	var macd:Float;
	var signal:Float;
	var histogram:Float;
}

/**
 * Zero-Lag MACD — ported from wickra-core's `ZeroLagMacd`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/zero_lag_macd.rs).
 *
 * The standard MACD topology with ZLEMA substituted for EMA everywhere:
 *
 *   macd_t      = ZLEMA(close, fast)_t − ZLEMA(close, slow)_t
 *   signal_t    = ZLEMA(macd, signal_period)_t
 *   histogram_t = macd_t − signal_t
 *
 * Defaults mirror MACD: `(fast = 12, slow = 26, signal = 9)`; `fast` must be
 * strictly less than `slow`. Series input (f64):
 * `zero_lag_macd(close, fast, slow, signal)`.
 */
class ZeroLagMacd implements MuseIndicator<Float, ZeroLagMacdOutput> {
	var fastPeriod:Int;
	var slowPeriod:Int;
	var signalPeriod:Int;
	var fast:Zlema;
	var slow:Zlema;
	var signal:Zlema;

	public function new(fast:Int, slow:Int, signal:Int) {
		if (fast <= 0 || slow <= 0 || signal <= 0) throw "ZeroLagMacd: periods must be > 0";
		if (fast >= slow) throw "ZeroLagMACD fast period must be strictly less than slow";
		fastPeriod = fast;
		slowPeriod = slow;
		signalPeriod = signal;
		this.fast = new Zlema(fast);
		this.slow = new Zlema(slow);
		this.signal = new Zlema(signal);
	}

	/** MACD-style defaults: `(fast = 12, slow = 26, signal = 9)`. */
	public static function classic():ZeroLagMacd {
		return new ZeroLagMacd(12, 26, 9);
	}

	/** Configured `(fast, slow, signal)`. */
	public function periods():{fast:Int, slow:Int, signal:Int} {
		return {fast: fastPeriod, slow: slowPeriod, signal: signalPeriod};
	}

	public function update(input:Float):Null<ZeroLagMacdOutput> {
		// Feed both inner ZLEMAs on every input so the slow one warms in
		// parallel with the fast one.
		var f = fast.update(input);
		var s = slow.update(input);
		if (f == null || s == null) return null;
		var macd = f - s;
		var sig = signal.update(macd);
		if (sig == null) return null;
		return { macd: macd, signal: sig, histogram: macd - sig };
	}

	public function reset():Void {
		fast.reset();
		slow.reset();
		signal.reset();
	}

	// ZLEMA(period) warmup is `(period − 1) / 2 + period` = `lag + period`.
	// The slow branch dominates; the signal ZLEMA then needs its own
	// `lag + period` MACD values on top.
	public function warmupPeriod():Int {
		var zlemaWarmup = function(period:Int):Int return Std.int((period - 1) / 2) + period;
		return zlemaWarmup(slowPeriod) + zlemaWarmup(signalPeriod) - 1;
	}

	public function isReady():Bool return signal.isReady();
	public function name():String return "ZeroLagMACD";

	public static function spec():IndicatorSpec {
		return {
			name: "zero_lag_macd", args: [TSeries, TWindow, TWindow, TWindow], ret: TObject([
				{name: "macd", ty: TScalar}, {name: "signal", ty: TScalar}, {name: "histogram", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var fast = IndicatorCache.intArg(args, 1, 12);
				var slow = IndicatorCache.intArg(args, 2, 26);
				var signalPeriod = IndicatorCache.intArg(args, 3, 9);
				var key = "zero_lag_macd:" + series + ":" + fast + ":" + slow + ":" + signalPeriod;
				var nanFill = { macd: Math.NaN, signal: Math.NaN, histogram: Math.NaN };
				return IndicatorCache.evalSeries(h, key, series, nanFill,
					() -> new ZeroLagMacd(fast, slow, signalPeriod), (i, v) -> (cast i : ZeroLagMacd).update(v));
			}
		};
	}
}
