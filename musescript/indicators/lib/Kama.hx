package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Kaufman's Adaptive Moving Average: an EMA-style average whose smoothing
 * constant is driven by an efficiency ratio — how much of the recent
 * back-and-forth price movement was actually net progress — so it moves
 * fast in a clean trend and slows to a crawl in a choppy market.
 *
 * ER    = |price_t - price_{t-erPeriod}| / sum(|price_i - price_{i-1}|, erPeriod)
 * SC    = (ER * (fastSC - slowSC) + slowSC)^2,
 *         fastSC = 2/(fastPeriod+1), slowSC = 2/(slowPeriod+1)
 * KAMA_t = KAMA_{t-1} + SC * (price_t - KAMA_{t-1})
 *
 * Seeded with the first price.
 */
class Kama implements MuseIndicator<Float, Float> {
	var erPeriod:Int;
	var fastSc:Float;
	var slowSc:Float;
	var prices:RingBuffer<Float>;
	var current:Null<Float>;

	public function new(erPeriod:Int, fastPeriod:Int, slowPeriod:Int) {
		if (erPeriod <= 0) throw "Kama: erPeriod must be > 0";
		this.erPeriod = erPeriod;
		fastSc = 2.0 / (fastPeriod + 1.0);
		slowSc = 2.0 / (slowPeriod + 1.0);
		reset();
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return current;

		if (current == null) {
			current = price;
			prices.push(price);
			return current;
		}

		prices.push(price);
		if (prices.length < erPeriod + 1) {
			current = price; // not enough history yet to compute ER; track price directly
			return current;
		}

		var change = Math.abs(prices.oldest(prices.length - 1) - prices.oldest(0));
		var volatility = 0.0;
		for (i in 1...prices.length) volatility += Math.abs(prices.oldest(i) - prices.oldest(i - 1));

		var er = volatility == 0.0 ? 0.0 : change / volatility;
		var sc = er * (fastSc - slowSc) + slowSc;
		sc = sc * sc;

		current = current + sc * (price - current);
		return current;
	}

	public function reset():Void {
		prices = new RingBuffer(erPeriod + 1);
		current = null;
	}

	public function warmupPeriod():Int return erPeriod + 1;
	public function isReady():Bool return prices.length == erPeriod + 1;
	public function name():String return "Kama";

	public static function spec():IndicatorSpec {
		return {
			name: "kama", args: [TSeries, TWindow, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var erPeriod = IndicatorCache.intArg(args, 1, 10);
				var fastPeriod = IndicatorCache.intArg(args, 2, 2);
				var slowPeriod = IndicatorCache.intArg(args, 3, 30);
				var key = "kama:" + series + ":" + erPeriod + ":" + fastPeriod + ":" + slowPeriod;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Kama(erPeriod, fastPeriod, slowPeriod), (i, v) -> (cast i : Kama).update(v));
			}
		};
	}
}
