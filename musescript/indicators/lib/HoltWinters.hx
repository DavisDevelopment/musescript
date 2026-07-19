package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Holt's Linear (double exponential smoothing, "Holt-Winters" without the
 * seasonal component, as commonly used in trading contexts): tracks a level
 * and a trend, each with its own smoothing weight, and outputs the
 * one-step-ahead forecast.
 *
 * level_t   = alpha*price_t + (1-alpha)*(level_{t-1} + trend_{t-1})
 * trend_t   = beta*(level_t - level_{t-1}) + (1-beta)*trend_{t-1}
 * output    = level_t + trend_t              (the 1-bar-ahead forecast)
 *
 * Seeded from the first two bars: level_1 = price_1, trend_1 = price_2 - price_1.
 */
class HoltWinters implements MuseIndicator<Float, Float> {
	var alpha:Float;
	var beta:Float;
	var level:Null<Float>;
	var trend:Float;
	var seeded:Bool;

	public function new(alpha:Float, beta:Float) {
		if (!Math.isFinite(alpha) || alpha <= 0.0 || alpha >= 1.0) throw "HoltWinters: alpha must be in (0, 1)";
		if (!Math.isFinite(beta) || beta <= 0.0 || beta >= 1.0) throw "HoltWinters: beta must be in (0, 1)";
		this.alpha = alpha;
		this.beta = beta;
		level = null;
		trend = 0.0;
		seeded = false;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return seeded ? level + trend : null;

		if (level == null) {
			level = price;
			return null;
		}
		if (!seeded) {
			trend = price - level;
			level = price;
			seeded = true;
			return level + trend;
		}

		var newLevel = alpha * price + (1.0 - alpha) * (level + trend);
		trend = beta * (newLevel - level) + (1.0 - beta) * trend;
		level = newLevel;
		return level + trend;
	}

	public function reset():Void {
		level = null;
		trend = 0.0;
		seeded = false;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return seeded;
	public function name():String return "HoltWinters";

	public static function spec():IndicatorSpec {
		return {
			name: "holt_winters", args: [TSeries, TScalar, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var alpha = IndicatorCache.floatArg(args, 1, 0.3);
				var beta = IndicatorCache.floatArg(args, 2, 0.1);
				var key = "holt_winters:" + series + ":" + alpha + ":" + beta;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new HoltWinters(alpha, beta), (i, v) -> (cast i : HoltWinters).update(v));
			}
		};
	}
}
