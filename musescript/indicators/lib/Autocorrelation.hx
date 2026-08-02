package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling lag-`lag` autocorrelation — ported from wickra-core's `Autocorrelation`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/autocorrelation.rs).
 *
 * Over the trailing window the Pearson correlation between the series and
 * itself shifted by `lag` is computed:
 *
 * ```text
 * y_i  for i = 0..period − 1
 * ACF(lag) = Σ ( (y_i − ȳ) · (y_{i + lag} − ȳ) ) / Σ ( y_i − ȳ )²
 * ```
 *
 * `+1` means a perfectly repeating pattern at the given lag; `−1` means a
 * perfect alternation. Values near `0` mean the series at `t` and `t − lag`
 * carry no linear relationship — a clean white-noise proxy. A flat window
 * has zero variance; the indicator returns `0` rather than dividing by zero.
 *
 * `period` must be strictly greater than `lag` so that at least two
 * `(y, y_lagged)` pairs exist.
 */
class Autocorrelation implements MuseIndicator<Float, Float> {
	var period:Int;
	var lag:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int, lag:Int) {
		if (lag <= 0) throw "Autocorrelation: lag must be >= 1";
		if (period <= lag) throw "Autocorrelation: period must be > lag";
		this.period = period;
		this.lag = lag;
		reset();
	}

	public function update(value:Float):Null<Float> {
		if (!Math.isFinite(value)) return null;
		window.push(value);
		if (window.length < period) return null;

		// ACF over the current window with a single pass.
		var n:Float = period;
		var mean = 0.0;
		for (v in window) mean += v;
		mean /= n;

		var denom = 0.0;
		var numer = 0.0;
		for (i in 0...period) {
			var d = window.oldest(i) - mean;
			denom += d * d;
		}
		for (i in 0...(period - lag)) {
			numer += (window.oldest(i) - mean) * (window.oldest(i + lag) - mean);
		}

		if (denom == 0.0) return 0.0;
		return numer / denom;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "Autocorrelation";

	public static function spec():IndicatorSpec {
		return {
			name: "autocorrelation", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var l = IndicatorCache.intArg(args, 1, 1);
				return IndicatorCache.evalSeries(h, "autocorrelation:" + p + ":" + l, "close", Math.NaN,
					() -> new Autocorrelation(p, l), (i, v) -> (cast i : Autocorrelation).update(v));
			}
		};
	}
}
