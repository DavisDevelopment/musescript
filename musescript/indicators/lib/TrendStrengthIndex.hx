package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Trend Strength Index — ported from wickra-core's `TrendStrengthIndex`
 * (vendor/wickra/crates/wickra-core/src/indicators/trend_strength_index.rs).
 *
 * Fits an OLS line to the last `period` prices against bar index and reports
 * the coefficient of determination `r²`, signed by the slope of the fit:
 *
 * r²  = (n·Σxy − Σx·Σy)² / [ (n·Σx² − (Σx)²)(n·Σy² − (Σy)²) ]
 * TSI = sign(slope) · r²
 *
 * A directional reading in `[−1, 1]`: near `+1` a strong clean uptrend, near
 * `−1` a strong downtrend, near `0` flat/noisy. A window of constant prices
 * (zero variance in y) returns `0`.
 */
class TrendStrengthIndex implements MuseIndicator<Float, Float> {
	var period:Int;
	var buf:Array<Float>;

	public function new(period:Int) {
		if (period == 0) throw "TrendStrengthIndex: period must be > 0";
		if (period == 1) throw "TrendStrengthIndex: period must be >= 2 for a regression";
		this.period = period;
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		buf.push(price);
		if (buf.length > period) buf.shift();
		if (buf.length < period) return null;

		var count = period;
		var sumX = 0.0;
		var sumXx = 0.0;
		var sumY = 0.0;
		var sumYy = 0.0;
		var sumXy = 0.0;
		for (idx in 0...buf.length) {
			var x = idx;
			var p = buf[idx];
			sumX += x;
			sumXx += x * x;
			sumY += p;
			sumYy += p * p;
			sumXy += x * p;
		}

		var cov = count * sumXy - sumX * sumY;
		var varX = count * sumXx - sumX * sumX;
		var varY = count * sumYy - sumY * sumY;
		if (varY <= 0.0) return 0.0;
		var r2 = (cov * cov) / (varX * varY);
		return cov >= 0.0 ? r2 : -r2;
	}

	public function reset():Void {
		buf = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return buf.length >= period;
	public function name():String return "TrendStrengthIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "trend_strength_index", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "trend_strength_index:" + series + ":" + p, series, Math.NaN,
					() -> new TrendStrengthIndex(p), (i, v) -> (cast i : TrendStrengthIndex).update(v));
			}
		};
	}
}
