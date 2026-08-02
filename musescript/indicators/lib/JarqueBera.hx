package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Jarque-Bera statistic: a normality test on the distribution of
 * bar-over-bar returns over a trailing window of `period` bars, combining
 * sample skewness and excess kurtosis into a single test statistic.
 *
 * JB = (n/6) * ( S^2 + (K - 3)^2 / 4 )
 *
 * where `S` is sample skewness and `K` is sample kurtosis of the window's
 * returns. Larger values mean the return distribution deviates more from
 * Gaussian (fat tails / skew); JB near 0 is consistent with normality.
 * Falls back to 0 when the window's returns are exactly constant (zero
 * variance — skewness/kurtosis undefined in the degenerate case).
 */
class JarqueBera implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var lastPrice:Null<Float>;

	public function new(period:Int) {
		if (period < 4) throw "JarqueBera: period must be >= 4";
		this.period = period;
		window = new RingBuffer(period);
		lastPrice = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;
		if (lastPrice == null) {
			lastPrice = price;
			return null;
		}
		var ret = price - lastPrice;
		lastPrice = price;

		window.push(ret);
		if (window.length < period) return null;

		var n = window.length;
		var mean = 0.0;
		for (r in window) mean += r;
		mean /= n;

		var m2 = 0.0, m3 = 0.0, m4 = 0.0;
		for (r in window) {
			var d = r - mean;
			var d2 = d * d;
			m2 += d2;
			m3 += d2 * d;
			m4 += d2 * d2;
		}
		m2 /= n; m3 /= n; m4 /= n;
		if (m2 == 0.0) return 0.0;

		var skew = m3 / Math.pow(m2, 1.5);
		var kurt = m4 / (m2 * m2);
		return (n / 6.0) * (skew * skew + (kurt - 3.0) * (kurt - 3.0) / 4.0);
	}

	public function reset():Void {
		window = new RingBuffer(period);
		lastPrice = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "JarqueBera";

	public static function spec():IndicatorSpec {
		return {
			name: "jarque_bera", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "jarque_bera:" + series + ":" + p, series, Math.NaN,
					() -> new JarqueBera(p), (i, v) -> (cast i : JarqueBera).update(v));
			}
		};
	}
}
