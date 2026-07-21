package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Sortino Ratio — ported from wickra-core's `SortinoRatio`
 * (vendor/wickra/crates/wickra-core/src/indicators/sortino_ratio.rs).
 *
 * Like the Sharpe Ratio but only penalises downside volatility — returns
 * below the minimum acceptable return (`mar`):
 *
 * downside_dev = sqrt( mean( min(0, r − mar)² over period ) )
 * Sortino      = (mean(r) − mar) / downside_dev
 *
 * Downside variance uses the population formula (`n` in the denominator).
 * If every return in the window is ≥ `mar` the downside deviation is 0 and
 * the indicator returns `0.0` rather than NaN.
 */
class SortinoRatio implements MuseIndicator<Float, Float> {
	var period:Int;
	var mar:Float;
	var window:Array<Float>;
	var sum:Float;

	public function new(period:Int, mar:Float) {
		if (period < 2) throw "SortinoRatio: sortino ratio needs period >= 2";
		this.period = period;
		this.mar = mar;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		if (window.length == period) {
			sum -= window.shift();
		}
		window.push(input);
		sum += input;
		if (window.length < period) return null;
		var n = period;
		var mean = sum / n;
		var downsideSq = 0.0;
		for (r in window) {
			var d = r - mar;
			if (d < 0.0) downsideSq += d * d;
		}
		var dd = Math.sqrt(downsideSq / n);
		if (dd == 0.0) return 0.0;
		return (mean - mar) / dd;
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "SortinoRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "sortino_ratio", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				var mar = IndicatorCache.floatArg(args, 2, 0.0);
				var key = "sortino_ratio:" + series + ":" + p + ":" + mar;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new SortinoRatio(p, mar), (i, v) -> (cast i : SortinoRatio).update(v));
			}
		};
	}
}
