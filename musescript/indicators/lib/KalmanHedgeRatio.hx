package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Kalman-filtered Hedge Ratio: a 1-dimensional Kalman filter tracking a
 * dynamic hedge ratio `beta` in the observation model `asset = beta * bench`,
 * with `beta` itself modeled as a random walk. Adapts to a changing
 * relationship between the two series faster than a fixed-window rolling
 * `Beta`, at the cost of being smoother/laggier when `Q` is small.
 *
 * predict: betaPred = beta,  Ppred = P + Q
 * update:  innovation = asset - betaPred*bench
 *          S = bench^2*Ppred + R
 *          K = Ppred*bench / S
 *          beta = betaPred + K*innovation
 *          P = (1 - K*bench) * Ppred
 *
 * Seeded with beta=0, P=1.
 */
class KalmanHedgeRatio implements MuseIndicator<KalmanHedgeRatioPair, Float> {
	var q:Float;
	var r:Float;
	var beta:Float;
	var p:Float;
	var hasEmitted:Bool;

	public function new(q:Float = 0.001, r:Float = 1.0) {
		if (!Math.isFinite(q) || q <= 0.0) throw "KalmanHedgeRatio: q must be positive and finite";
		if (!Math.isFinite(r) || r <= 0.0) throw "KalmanHedgeRatio: r must be positive and finite";
		this.q = q;
		this.r = r;
		beta = 0.0;
		p = 1.0;
		hasEmitted = false;
	}

	public function update(input:KalmanHedgeRatioPair):Null<Float> {
		var asset = input.a;
		var bench = input.b;
		if (!Math.isFinite(asset) || !Math.isFinite(bench)) return hasEmitted ? beta : null;

		var betaPred = beta;
		var pPred = p + q;

		var innovation = asset - betaPred * bench;
		var s = bench * bench * pPred + r;
		var k = s == 0.0 ? 0.0 : pPred * bench / s;

		beta = betaPred + k * innovation;
		p = (1.0 - k * bench) * pPred;
		hasEmitted = true;
		return beta;
	}

	public function reset():Void {
		beta = 0.0;
		p = 1.0;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "KalmanHedgeRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "kalman_hedge_ratio", args: [TSeries, TSeries, TScalar, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var q = IndicatorCache.floatArg(args, 2, 0.001);
				var r = IndicatorCache.floatArg(args, 3, 1.0);
				var key = "kalman_hedge_ratio:" + seriesA + ":" + seriesB + ":" + q + ":" + r;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new KalmanHedgeRatio(q, r), (i, a, b) -> (cast i : KalmanHedgeRatio).update({ a: a, b: b }));
			}
		};
	}
}

typedef KalmanHedgeRatioPair = { a: Float, b: Float };
