package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * McGinley Dynamic: a self-adjusting moving average that speeds up in fast
 * markets and slows down in slow ones, automatically — the adjustment
 * factor is derived from price's own ratio to the prior average rather than
 * a fixed smoothing constant.
 *
 * MD_t = MD_{t-1} + (price_t - MD_{t-1}) / ( N * (price_t / MD_{t-1})^4 )
 *
 * Seeded with the first price. Guards against a zero/negative prior value
 * (which the ratio's 4th power would otherwise blow up on) by falling back
 * to a plain price-tracking step in that degenerate case.
 */
class McginleyDynamic implements MuseIndicator<Float, Float> {
	var n:Float;
	var current:Null<Float>;

	public function new(n:Int) {
		if (n <= 0) throw "McginleyDynamic: n must be > 0";
		this.n = n;
		current = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return current;
		if (current == null) {
			current = price;
			return current;
		}
		if (current <= 0.0) {
			current = price;
			return current;
		}
		var ratio = price / current;
		var denom = n * ratio * ratio * ratio * ratio;
		current = current + (price - current) / denom;
		return current;
	}

	public function reset():Void {
		current = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return current != null;
	public function name():String return "McginleyDynamic";

	public static function spec():IndicatorSpec {
		return {
			name: "mcginley_dynamic", args: [TSeries, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var n = IndicatorCache.intArg(args, 1, 10);
				return IndicatorCache.evalSeries(h, "mcginley_dynamic:" + series + ":" + n, series, Math.NaN,
					() -> new McginleyDynamic(n), (i, v) -> (cast i : McginleyDynamic).update(v));
			}
		};
	}
}
