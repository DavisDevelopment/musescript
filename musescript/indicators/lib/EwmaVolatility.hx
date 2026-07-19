package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * EWMA Volatility (RiskMetrics-style): an exponentially-weighted running
 * variance of log-returns, more responsive to recent shocks than a fixed
 * rolling-window stddev.
 *
 * r_t      = ln(price_t / price_{t-1})
 * var_t    = lambda * var_{t-1} + (1 - lambda) * r_t^2
 * output   = sqrt(var_t)
 *
 * Seeded with `r_1^2` as `var_1` (first available return). Classic
 * RiskMetrics default: lambda = 0.94.
 */
class EwmaVolatility implements MuseIndicator<Float, Float> {
	var lambda:Float;
	var lastPrice:Null<Float>;
	var variance:Null<Float>;

	public function new(lambda:Float = 0.94) {
		if (!Math.isFinite(lambda) || lambda <= 0.0 || lambda >= 1.0) throw "EwmaVolatility: lambda must be in (0, 1)";
		this.lambda = lambda;
		lastPrice = null;
		variance = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price) || price <= 0.0) return variance == null ? null : Math.sqrt(variance);
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var r = Math.log(price / lastPrice);
		lastPrice = price;

		variance = if (variance == null) r * r else lambda * variance + (1.0 - lambda) * r * r;
		return Math.sqrt(variance);
	}

	public function reset():Void {
		lastPrice = null;
		variance = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return variance != null;
	public function name():String return "EwmaVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "ewma_volatility", args: [TSeries, TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var lambda = IndicatorCache.floatArg(args, 1, 0.94);
				return IndicatorCache.evalSeries(h, "ewma_volatility:" + series + ":" + lambda, series, Math.NaN,
					() -> new EwmaVolatility(lambda), (i, v) -> (cast i : EwmaVolatility).update(v));
			}
		};
	}
}
