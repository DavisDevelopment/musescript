package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Geometric Moving Average: the rolling geometric mean of the trailing
 * `period` values, computed via a sum-of-logs to stay numerically stable.
 *
 * GMA = exp( mean( ln(price), period ) ) = (prod of window)^(1/period)
 *
 * Only defined for strictly positive inputs (as prices are); a non-positive
 * input is treated as a gap and ignored (state untouched).
 */
class GeometricMa implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var sumLog:Float;

	public function new(period:Int) {
		if (period <= 0) throw "GeometricMa: period must be > 0";
		this.period = period;
		window = new RingBuffer(period);
		sumLog = 0.0;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price) || price <= 0.0) return window.length == period ? Math.exp(sumLog / period) : null;
		var logP = Math.log(price);
		var wasFull = window.isFull();
		var old = window.push(logP);
		if (wasFull) sumLog -= old;
		sumLog += logP;
		if (window.length < period) return null;
		return Math.exp(sumLog / period);
	}

	public function reset():Void {
		window = new RingBuffer(period);
		sumLog = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "GeometricMa";

	public static function spec():IndicatorSpec {
		return {
			name: "geometric_ma", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "geometric_ma:" + series + ":" + p, series, Math.NaN,
					() -> new GeometricMa(p), (i, v) -> (cast i : GeometricMa).update(v));
			}
		};
	}
}
