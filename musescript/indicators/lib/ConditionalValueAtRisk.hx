package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Conditional Value at Risk (Expected Shortfall): the mean loss among the
 * worst `(1 - confidence)` fraction of returns in a trailing window of
 * `period` single-bar returns.
 *
 * returns  = { (price_i - price_{i-1}) / price_{i-1} }  over the window
 * k        = max(1, ceil((1 - confidence) * n))
 * CVaR     = -mean(worst k returns)      (reported as a positive loss magnitude)
 *
 * A more conservative tail-risk measure than plain VaR (the k-th worst
 * return alone), since it averages the whole worst tail rather than just its
 * boundary.
 */
class ConditionalValueAtRisk implements MuseIndicator<Float, Float> {
	var period:Int;
	var confidence:Float;
	var prices:Array<Float>;

	public function new(period:Int, confidence:Float) {
		if (period < 2) throw "ConditionalValueAtRisk: period must be >= 2";
		if (!Math.isFinite(confidence) || confidence <= 0.0 || confidence >= 1.0) {
			throw "ConditionalValueAtRisk: confidence must be in (0, 1)";
		}
		this.period = period;
		this.confidence = confidence;
		prices = [];
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		// `period` returns need `period + 1` prices.
		if (prices.length == period + 1) prices.shift();
		prices.push(price);
		if (prices.length < period + 1) return null;

		var returns:Array<Float> = [];
		for (i in 1...prices.length) {
			var prev = prices[i - 1];
			if (prev != 0.0) returns.push((prices[i] - prev) / prev);
		}
		if (returns.length == 0) return 0.0;
		returns.sort((a, b) -> a < b ? -1 : (a > b ? 1 : 0));

		var k = Math.ceil((1.0 - confidence) * returns.length);
		if (k < 1) k = 1;
		if (k > returns.length) k = returns.length;

		var sum = 0.0;
		for (i in 0...k) sum += returns[i];
		return -(sum / k);
	}

	public function reset():Void {
		prices = [];
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return prices.length == period + 1;
	public function name():String return "ConditionalValueAtRisk";

	public static function spec():IndicatorSpec {
		return {
			name: "conditional_value_at_risk", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 60);
				var conf = IndicatorCache.floatArg(args, 2, 0.95);
				var key = "conditional_value_at_risk:" + series + ":" + p + ":" + conf;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new ConditionalValueAtRisk(p, conf), (i, v) -> (cast i : ConditionalValueAtRisk).update(v));
			}
		};
	}
}
