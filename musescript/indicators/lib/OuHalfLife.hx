package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ornstein-Uhlenbeck Half-Life: how many bars a mean-reverting spread
 * between two series takes to close half the distance back to its own
 * rolling mean — estimated via an AR(1) regression of the spread's
 * bar-over-bar change against its own lagged level.
 *
 * spread_t   = a_t - b_t
 * regress:  spread_t - spread_{t-1}  ~  theta * spread_{t-1}   (OLS slope theta)
 * halfLife  = -ln(2) / theta      (only meaningful when theta < 0, i.e.
 *                                  genuinely mean-reverting)
 *
 * Falls back to 0 when theta >= 0 (the spread isn't mean-reverting over the
 * window — a half-life isn't defined for a random walk or diverging
 * series).
 */
class OuHalfLife implements MuseIndicator<OuHalfLifePair, Float> {
	var period:Int;
	var window:Array<Float>;

	public function new(period:Int) {
		if (period < 3) throw "OuHalfLife: period must be >= 3";
		this.period = period;
		window = [];
	}

	public function update(input:OuHalfLifePair):Null<Float> {
		var spread = input.a - input.b;
		if (!Math.isFinite(spread)) return null;
		if (window.length == period + 1) window.shift();
		window.push(spread);
		if (window.length < period + 1) return null;

		// Regress delta_t = spread_t - spread_{t-1} against x_t = spread_{t-1}.
		var xs:Array<Float> = [];
		var ys:Array<Float> = [];
		for (i in 1...window.length) {
			xs.push(window[i - 1]);
			ys.push(window[i] - window[i - 1]);
		}
		var n = xs.length;
		var meanX = 0.0, meanY = 0.0;
		for (x in xs) meanX += x;
		for (y in ys) meanY += y;
		meanX /= n; meanY /= n;

		var num = 0.0, den = 0.0;
		for (i in 0...n) {
			var dx = xs[i] - meanX;
			num += dx * (ys[i] - meanY);
			den += dx * dx;
		}
		if (den == 0.0) return 0.0;
		var theta = num / den;
		if (theta >= 0.0) return 0.0;
		return -Math.log(2.0) / theta;
	}

	public function reset():Void {
		window = [];
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period + 1;
	public function name():String return "OuHalfLife";

	public static function spec():IndicatorSpec {
		return {
			name: "ou_half_life", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "ou_half_life:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new OuHalfLife(p), (i, a, b) -> (cast i : OuHalfLife).update({ a: a, b: b }));
			}
		};
	}
}

@:structInit
class OuHalfLifePair {
	public var a:Float;
	public var b:Float;
}
