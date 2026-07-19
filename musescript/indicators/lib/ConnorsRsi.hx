package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Rsi;
import musescript.types.MuseType;

/**
 * Connors RSI: a composite short-term mean-reversion oscillator averaging
 * three sub-signals over a trailing window.
 *
 * 1. RSI(close, rsiPeriod)                     — classic price momentum.
 * 2. RSI(streak, streakPeriod)                  — momentum of the "up/down
 *    streak" length (consecutive same-direction closes: +1, +2, ... on
 *    up-streaks, -1, -2, ... on down-streaks, 0 on the very first bar / a
 *    flat close).
 * 3. PercentRank(1-bar return, rankPeriod)      — what fraction of the
 *    trailing `rankPeriod` 1-bar returns are <= today's, as a 0-100 percentile.
 *
 * ConnorsRSI = ( RSI_price + RSI_streak + PercentRank ) / 3
 *
 * Classic parameters: rsiPeriod=3, streakPeriod=2, rankPeriod=100.
 */
class ConnorsRsi implements MuseIndicator<Float, Float> {
	var priceRsi:Rsi;
	var streakRsi:Rsi;
	var rankPeriod:Int;
	var returns:Array<Float>;
	var lastPrice:Null<Float>;
	var streak:Float;

	public function new(rsiPeriod:Int, streakPeriod:Int, rankPeriod:Int) {
		if (rankPeriod < 2) throw "ConnorsRsi: rankPeriod must be >= 2";
		priceRsi = new Rsi(rsiPeriod);
		streakRsi = new Rsi(streakPeriod);
		this.rankPeriod = rankPeriod;
		returns = [];
		lastPrice = null;
		streak = 0.0;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return null;

		var priceR = priceRsi.update(price);

		if (lastPrice == null) {
			streak = 0.0;
		} else if (price > lastPrice) {
			streak = streak > 0.0 ? streak + 1.0 : 1.0;
		} else if (price < lastPrice) {
			streak = streak < 0.0 ? streak - 1.0 : -1.0;
		} else {
			streak = 0.0;
		}
		var streakR = streakRsi.update(streak);

		var pctRank:Null<Float> = null;
		if (lastPrice != null && lastPrice != 0.0) {
			var ret = (price - lastPrice) / lastPrice;
			if (returns.length == rankPeriod) returns.shift();
			returns.push(ret);
			if (returns.length == rankPeriod) {
				var below = 0;
				for (r in returns) if (r < ret) below++;
				pctRank = below / rankPeriod * 100.0;
			}
		}
		lastPrice = price;

		if (priceR == null || streakR == null || pctRank == null) return null;
		return (priceR + streakR + pctRank) / 3.0;
	}

	public function reset():Void {
		priceRsi.reset();
		streakRsi.reset();
		returns = [];
		lastPrice = null;
		streak = 0.0;
	}

	public function warmupPeriod():Int {
		var m = priceRsi.warmupPeriod();
		if (streakRsi.warmupPeriod() > m) m = streakRsi.warmupPeriod();
		if (rankPeriod + 1 > m) m = rankPeriod + 1;
		return m;
	}
	public function isReady():Bool return priceRsi.isReady() && streakRsi.isReady() && returns.length == rankPeriod;
	public function name():String return "ConnorsRsi";

	public static function spec():IndicatorSpec {
		return {
			name: "connors_rsi", args: [TSeries, TWindow, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var rsiPeriod = IndicatorCache.intArg(args, 1, 3);
				var streakPeriod = IndicatorCache.intArg(args, 2, 2);
				var rankPeriod = IndicatorCache.intArg(args, 3, 100);
				var key = "connors_rsi:" + series + ":" + rsiPeriod + ":" + streakPeriod + ":" + rankPeriod;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new ConnorsRsi(rsiPeriod, streakPeriod, rankPeriod), (i, v) -> (cast i : ConnorsRsi).update(v));
			}
		};
	}
}
