package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Log Return: the bar-over-bar log return, `ln(price_t / price_{t-1})` —
 * the primitive return measure most of this port's statistical indicators
 * (`HistoricalVolatility`, `BipowerVariation`, `EwmaVolatility`, ...) are
 * built on, exposed directly as its own indicator.
 */
class LogReturn implements MuseIndicator<Float, Float> {
	var lastPrice:Null<Float>;

	public function new() {
		lastPrice = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price) || price <= 0.0) return null;
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var r = Math.log(price / lastPrice);
		lastPrice = price;
		return r;
	}

	public function reset():Void {
		lastPrice = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return lastPrice != null;
	public function name():String return "LogReturn";

	public static function spec():IndicatorSpec {
		return {
			name: "log_return", args: [TSeries], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "log_return:" + series, series, Math.NaN,
					() -> new LogReturn(), (i, v) -> (cast i : LogReturn).update(v));
			}
		};
	}
}
