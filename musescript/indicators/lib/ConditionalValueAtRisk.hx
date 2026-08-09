package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.SortedWindow;
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
 *
 * Prices live in a `RingBuffer`. Single-period returns are themselves a stable
 * chronological ring (only the oldest pair drops and one new pair is added
 * each bar when no denominator is zero), so they ride a `SortedWindow`. If any
 * price used as a return denominator is zero, returns are rebuilt from the
 * price ring to stay bit-identical to the old skip-zero semantics.
 */
class ConditionalValueAtRisk implements MuseIndicator<Float, Float> {
	var period:Int;
	var confidence:Float;
	var prices:RingBuffer<Float>;
	var returns:SortedWindow;

	public function new(period:Int, confidence:Float) {
		if (period < 2) throw "ConditionalValueAtRisk: period must be >= 2";
		if (!Math.isFinite(confidence) || confidence <= 0.0 || confidence >= 1.0) {
			throw "ConditionalValueAtRisk: confidence must be in (0, 1)";
		}
		this.period = period;
		this.confidence = confidence;
		prices = new RingBuffer(period + 1);
		returns = new SortedWindow(period);
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		// `period` returns need `period + 1` prices.
		// Capture fullness before push: JS Null<Float> of 0.0 == null.
		var wasFull = prices.isFull();
		prices.push(price);
		if (prices.length < period + 1) return null;

		if (hasZeroDenominator() || !wasFull || returns.length != period) {
			rebuildReturns();
		} else {
			var prev = prices.oldest(prices.length - 2);
			// wasFull ∧ no zero denoms ⇒ prev != 0 (denominator of the new return).
			returns.push((price - prev) / prev);
		}

		var n = returns.length;
		if (n == 0) return 0.0;

		var k = Math.ceil((1.0 - confidence) * n);
		if (k < 1) k = 1;
		if (k > n) k = n;

		var sum = 0.0;
		for (i in 0...k) sum += returns.order(i);
		return -(sum / k);
	}

	function hasZeroDenominator():Bool {
		// Denominators are every price except the newest.
		var last = prices.length - 1;
		for (i in 0...last) {
			if (prices.oldest(i) == 0.0) return true;
		}
		return false;
	}

	function rebuildReturns():Void {
		returns.reset();
		for (i in 1...prices.length) {
			var prev = prices.oldest(i - 1);
			if (prev != 0.0) returns.push((prices.oldest(i) - prev) / prev);
		}
	}

	public function reset():Void {
		prices = new RingBuffer(period + 1);
		returns = new SortedWindow(period);
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
