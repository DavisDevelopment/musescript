package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Hasbrouck Information Share — ported from wickra-core's
 * `HasbrouckInformationShare`
 * (vendor/wickra/crates/wickra-core/src/indicators/hasbrouck_information_share.rs).
 *
 * The share of price-discovery attributable to the FIRST of two synchronised
 * price series (e.g. the same asset on two venues):
 *
 * rx_t = x_t − x_{t−1},  ry_t = y_t − y_{t−1}
 * IS_x = var(rx) / ( var(rx) + var(ry) )   over the window, ∈ [0, 1]
 *
 * This streaming form is the variance-ratio proxy for Hasbrouck's full
 * VECM-based measure: above 0.5 venue x leads price discovery, below 0.5 it
 * follows. If both series are flat it reports the neutral 0.5. The first
 * value lands after `period + 1` inputs; each `update` is O(1).
 *
 * Pair input: (price_x, price_y).
 */
class HasbrouckInformationShare implements MuseIndicator<HisPair, Float> {
	var period:Int;
	var prev:Null<HisPair>;
	var window:Array<HisPair>;
	var sumX:Float;
	var sumY:Float;
	var sumXx:Float;
	var sumYy:Float;

	public function new(period:Int) {
		if (period < 2) throw "HasbrouckInformationShare: information share needs period >= 2";
		this.period = period;
		reset();
	}

	public function update(input:HisPair):Null<Float> {
		var x = input.a;
		var y = input.b;
		if (!Math.isFinite(x) || !Math.isFinite(y)) return null;
		if (prev == null) {
			prev = { a: x, b: y };
			return null;
		}
		var px = prev.a;
		var py = prev.b;
		prev = { a: x, b: y };
		var rx = x - px;
		var ry = y - py;
		if (window.length == period) {
			var old = window.shift();
			sumX -= old.a;
			sumY -= old.b;
			sumXx -= old.a * old.a;
			sumYy -= old.b * old.b;
		}
		window.push({ a: rx, b: ry });
		sumX += rx;
		sumY += ry;
		sumXx += rx * rx;
		sumYy += ry * ry;
		if (window.length < period) return null;
		var n:Float = period;
		var mx = sumX / n;
		var my = sumY / n;
		var varX = sumXx / n - mx * mx;
		if (varX < 0.0) varX = 0.0;
		var varY = sumYy / n - my * my;
		if (varY < 0.0) varY = 0.0;
		var total = varX + varY;
		return total > 0.0 ? varX / total : 0.5;
	}

	public function reset():Void {
		prev = null;
		window = [];
		sumX = 0.0;
		sumY = 0.0;
		sumXx = 0.0;
		sumYy = 0.0;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period;
	public function name():String return "HasbrouckInformationShare";

	public static function spec():IndicatorSpec {
		return {
			name: "hasbrouck_information_share", args: [TSeries, TSeries, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var p = IndicatorCache.intArg(args, 2, 20);
				var key = "hasbrouck_information_share:" + seriesA + ":" + seriesB + ":" + p;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new HasbrouckInformationShare(p), (i, a, b) -> (cast i : HasbrouckInformationShare).update({ a: a, b: b }));
			}
		};
	}
}

typedef HisPair = { a: Float, b: Float };
