package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * AR(1) autoregression coefficient of the spread of two series — ported from
 * wickra-core's `SpreadAr1Coefficient`
 * (vendor/wickra/crates/wickra-core/src/indicators/spread_ar1_coefficient.rs).
 *
 * Each update takes one (a, b) price pair and forms the spread s_t = a_t − b_t.
 * Over the trailing window of `period` spreads it fits the discrete AR(1)
 * model by OLS of the level on its own lag:
 *
 *   s_t = ρ · s_{t−1} + c + ε_t
 *   ρ   = cov(s_{t−1}, s_t) / var(s_{t−1})
 *
 * ρ near 0 means very strong mean reversion, ρ near 1 a random walk (no
 * cointegration), ρ > 1 an explosive spread. A flat spread over the window
 * (var = 0) has no defined slope and returns 0.
 */
class SpreadAr1Coefficient implements MuseIndicator<SpreadAr1Pair, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 3) throw "SpreadAr1Coefficient: period must be >= 3";
		this.period = period;
		window = [];
	}

	public function update(input:SpreadAr1Pair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!Math.isFinite(a) || !Math.isFinite(b)) return null;
		if (window.length == period) window.shift();
		window.push(a - b);
		if (window.length < period) return null;
		// OLS slope ρ of the level on its own lag over the window.
		var count:Float = window.length - 1;
		var sumLevel = 0.0;
		var sumNext = 0.0;
		var sumLl = 0.0;
		var sumLn = 0.0;
		for (i in 0...window.length - 1) {
			var level = window[i];
			var next = window[i + 1];
			sumLevel += level;
			sumNext += next;
			sumLl += level * level;
			sumLn += level * next;
		}
		var meanLevel = sumLevel / count;
		var meanNext = sumNext / count;
		var varLevel = sumLl / count - meanLevel * meanLevel;
		if (varLevel <= 0.0) {
			// Flat spread: the regression has no defined slope.
			return 0.0;
		}
		var cov = sumLn / count - meanLevel * meanNext;
		return cov / varLevel;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "SpreadAr1Coefficient";

	public static function spec():IndicatorSpec {
		return {
			name: "spread_ar1_coefficient", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 40);
				var key = "spread_ar1_coefficient:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new SpreadAr1Coefficient(p),
					(i, a, b) -> (cast i : SpreadAr1Coefficient).update({a: a, b: b}));
			}
		};
	}
}

@:structInit
class SpreadAr1Pair {
	public var a:Float;
	public var b:Float;
}
