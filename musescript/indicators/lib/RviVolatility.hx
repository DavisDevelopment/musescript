package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Relative Volatility Index — ported from wickra-core's `RviVolatility`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rvi_volatility.rs).
 *
 * Donald Dorsey's RSI-shaped volatility gauge:
 *
 *   sd_t      = stddev_pop(close over `period`)
 *   up_t      = sd_t if close_t > close_{t-1}, else 0
 *   down_t    = sd_t if close_t < close_{t-1}, else 0
 *   RVI_t     = 100 * Wilder(up, period) / (Wilder(up, period) + Wilder(down, period))
 *
 * Bounded on [0, 100]; a completely flat series returns 50 by the same
 * undefined-RS convention as RSI. Non-finite input leaves state untouched
 * and returns the last value.
 */
class RviVolatility implements MuseIndicator<Float, Float> {
	public var period(default, null):Int;
	// Rolling-stddev state.
	var window:Array<Float>;
	var sum:Float;
	var sumSq:Float;
	// Direction tracking.
	var prevClose:Null<Float>;
	// Wilder-smoothed up/down volatility.
	var seedUp:Array<Float>;
	var seedDown:Array<Float>;
	var avgUp:Null<Float>;
	var avgDown:Null<Float>;
	var lastValue:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "RviVolatility: period must be > 0";
		if (period < 2) throw "RVI period must be >= 2";
		this.period = period;
		reset();
	}

	/** Current value if available (null during warmup). */
	public function value():Null<Float> return lastValue;

	static function ratio(avgUp:Float, avgDown:Float):Float {
		var denom = avgUp + avgDown;
		// No volatility on either side: match RSI's undefined-RS convention.
		return denom == 0.0 ? 50.0 : 100.0 * avgUp / denom;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input leaves state untouched, mirrors StdDev / Rsi.
			return lastValue;
		}

		// 1. Roll the standard-deviation window.
		if (window.length == period) {
			var old = window.shift();
			sum -= old;
			sumSq -= old * old;
		}
		window.push(input);
		sum += input;
		sumSq += input * input;

		if (window.length < period) {
			// Track previous close from the very first input so that the first
			// ready stddev sample is paired with a valid direction.
			prevClose = input;
			return null;
		}

		var n:Float = period;
		var mean = sum / n;
		// Population variance with a non-negativity clamp for FP cancellation.
		var variance = Math.max(sumSq / n - mean * mean, 0.0);
		var sd = Math.sqrt(variance);

		// 2. Classify the stddev sample as up- or down-volatility.
		var prev:Float = prevClose;
		var up = 0.0;
		var down = 0.0;
		if (input > prev) up = sd;
		else if (input < prev) down = sd;
		prevClose = input;

		// 3. Wilder-smooth the up/down series.
		if (avgUp != null && avgDown != null) {
			var newAu = (avgUp * (n - 1.0) + up) / n;
			var newAd = (avgDown * (n - 1.0) + down) / n;
			avgUp = newAu;
			avgDown = newAd;
			var v = ratio(newAu, newAd);
			lastValue = v;
			return v;
		}

		seedUp.push(up);
		seedDown.push(down);
		if (seedUp.length == period) {
			var su = 0.0;
			for (x in seedUp) su += x;
			var sdn = 0.0;
			for (x in seedDown) sdn += x;
			var au = su / n;
			var ad = sdn / n;
			avgUp = au;
			avgDown = ad;
			var v = ratio(au, ad);
			lastValue = v;
			return v;
		}
		return null;
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
		sumSq = 0.0;
		prevClose = null;
		seedUp = [];
		seedDown = [];
		avgUp = null;
		avgDown = null;
		lastValue = null;
	}

	public function warmupPeriod():Int return 2 * period - 1;
	public function isReady():Bool return lastValue != null;
	public function name():String return "RVIVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "rvi_volatility", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "rvi_volatility:" + series + ":" + p, series, Math.NaN,
					() -> new RviVolatility(p), (i, v) -> (cast i : RviVolatility).update(v));
			}
		};
	}
}
