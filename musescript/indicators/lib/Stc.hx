package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Schaff Trend Cycle (STC) — ported from wickra-core's `Stc`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/stc.rs).
 *
 * Doug Schaff's doubly-Stochastic-smoothed MACD producing a bounded
 * `[0, 100]` reading:
 *
 *   macd_t = EMA(close, fast) − EMA(close, slow)
 *   %K     = stochastic of macd over `period`; %D = half-EMA of %K
 *   %K2    = stochastic of %D over `period`;  STC = half-EMA of %K2
 *
 * Wickra uses `factor = 0.5` and Schaff's recommended defaults
 * `(fast = 23, slow = 50, period = 10)`. Stochastic stages clamp to `0` when
 * the window range collapses. Series input (f64):
 * `stc(close, fast, slow, period, factor)`.
 */
class Stc implements MuseIndicator<Float, Float> {
	var fastPeriod:Int;
	var slowPeriod:Int;
	var schaffPeriod:Int;
	var factor:Float;
	var fastEma:Ema;
	var slowEma:Ema;
	var macdWindow:RingBuffer<Float>;
	var dWindow:RingBuffer<Float>;
	var lastD:Null<Float>;
	var lastValue:Null<Float>;

	public function new(fast:Int, slow:Int, schaffPeriod:Int, factor:Float) {
		if (fast <= 0 || slow <= 0 || schaffPeriod <= 0) throw "Stc: periods must be > 0";
		if (fast >= slow) throw "STC fast period must be strictly less than slow";
		if (!Math.isFinite(factor) || factor <= 0.0 || factor > 1.0) {
			throw "STC factor must be a finite value in (0, 1]";
		}
		fastPeriod = fast;
		slowPeriod = slow;
		this.schaffPeriod = schaffPeriod;
		this.factor = factor;
		fastEma = new Ema(fast);
		slowEma = new Ema(slow);
		macdWindow = new RingBuffer(schaffPeriod);
		dWindow = new RingBuffer(schaffPeriod);
		lastD = null;
		lastValue = null;
	}

	/** Schaff's recommended defaults `(23, 50, 10, 0.5)`. */
	public static function classic():Stc {
		return new Stc(23, 50, 10, 0.5);
	}

	/** Configured `(fast, slow, schaff_period, factor)`. */
	public function params():{fast:Int, slow:Int, schaff_period:Int, factor:Float} {
		return {fast: fastPeriod, slow: slowPeriod, schaff_period: schaffPeriod, factor: factor};
	}

	static function rollingMinMax(window:RingBuffer<Float>):{lo:Float, hi:Float} {
		var lo = Math.POSITIVE_INFINITY;
		var hi = Math.NEGATIVE_INFINITY;
		for (i in 0...window.length) {
			var v = window.at(i);
			if (v < lo) lo = v;
			if (v > hi) hi = v;
		}
		return {lo: lo, hi: hi};
	}

	public function update(input:Float):Null<Float> {
		// Feed both EMAs on every input (mirrors Rust: both fed before `?`).
		var f = fastEma.update(input);
		var s = slowEma.update(input);
		if (f == null || s == null) return null;
		var macd = f - s;

		macdWindow.push(macd);
		if (macdWindow.length < schaffPeriod) return null;

		var mm = rollingMinMax(macdWindow);
		var k = mm.hi > mm.lo ? 100.0 * (macd - mm.lo) / (mm.hi - mm.lo) : 0.0;

		var d:Float;
		if (lastD != null) {
			var prevD:Float = lastD;
			d = prevD + factor * (k - prevD);
		} else {
			d = k;
		}
		lastD = d;

		dWindow.push(d);
		if (dWindow.length < schaffPeriod) return null;

		var mmD = rollingMinMax(dWindow);
		var k2 = mmD.hi > mmD.lo ? 100.0 * (d - mmD.lo) / (mmD.hi - mmD.lo) : 0.0;

		var stc:Float;
		if (lastValue != null) {
			var prevStc:Float = lastValue;
			stc = prevStc + factor * (k2 - prevStc);
		} else {
			stc = k2;
		}
		lastValue = stc;
		return Math.min(Math.max(stc, 0.0), 100.0);
	}

	public function reset():Void {
		fastEma.reset();
		slowEma.reset();
		macdWindow = new RingBuffer(schaffPeriod);
		dWindow = new RingBuffer(schaffPeriod);
		lastD = null;
		lastValue = null;
	}

	// Slow EMA emits at `slow` inputs; the macd-window needs `schaff_period − 1`
	// more, and the d-window another `schaff_period − 1` after that.
	public function warmupPeriod():Int return slowPeriod + 2 * (schaffPeriod - 1);
	public function isReady():Bool return lastValue != null && dWindow.length == schaffPeriod;
	public function name():String return "STC";

	public static function spec():IndicatorSpec {
		return {
			name: "stc", args: [TSeries, TWindow, TWindow, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var fast = IndicatorCache.intArg(args, 1, 23);
				var slow = IndicatorCache.intArg(args, 2, 50);
				var p = IndicatorCache.intArg(args, 3, 10);
				var factor = IndicatorCache.floatArg(args, 4, 0.5);
				var key = "stc:" + series + ":" + fast + ":" + slow + ":" + p + ":" + factor;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Stc(fast, slow, p, factor), (i, v) -> (cast i : Stc).update(v));
			}
		};
	}
}
