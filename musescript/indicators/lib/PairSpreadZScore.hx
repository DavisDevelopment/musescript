package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Pair Spread Z-Score — ported from wickra-core's `PairSpreadZScore`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/pair_spread_zscore.rs).
 *
 * The mean-reversion signal for cointegrated pairs: standardised log-spread
 * between two assets. Over a rolling hedge-ratio window and a rolling spread
 * z-score window, the indicator:
 *
 * 1. Fits hedge ratio β via OLS of ln(a) on ln(b);
 * 2. Computes spread s = ln(a) − β·ln(b);
 * 3. Z-scores the spread over its trailing window.
 *
 * Large positive z means `a` is rich relative to `b` (sell the spread); large
 * negative means `a` is cheap (buy); z near zero means they're at parity.
 */
class PairSpreadZScore implements MuseIndicator<PairSpreadPair, Float> {
	var betaPeriod:Int;
	var zPeriod:Int;
	// Rolling OLS of y = ln(a) on x = ln(b).
	var reg:RingBuffer<PairSpreadXY>;
	var sumX:Float;
	var sumY:Float;
	var sumXx:Float;
	var sumXy:Float;
	// Rolling mean/variance of the spread.
	var spreads:RingBuffer<Float>;
	var sumS:Float;
	var sumSs:Float;

	public function new(betaPeriod:Int, zPeriod:Int) {
		if (betaPeriod < 2) throw "PairSpreadZScore: beta_period must be >= 2";
		if (zPeriod < 2) throw "PairSpreadZScore: z_period must be >= 2";
		this.betaPeriod = betaPeriod;
		this.zPeriod = zPeriod;
		reset();
	}

	function hedgeRatio():Null<Float> {
		if (reg.length < betaPeriod) return null;
		var n = betaPeriod;
		var meanX = sumX / n;
		var meanY = sumY / n;
		var varX = (sumXx / n - meanX * meanX);
		if (varX < 0.0) varX = 0.0;
		if (varX == 0.0) return 0.0;
		var cov = sumXy / n - meanX * meanY;
		return cov / varX;
	}

	function pushSpread(s:Float):Null<Float> {
		var wasFull = spreads.isFull();
		var old = spreads.push(s);
		if (wasFull) {
			sumS -= old;
			sumSs -= old * old;
		}
		sumS += s;
		sumSs += s * s;
		if (spreads.length < zPeriod) return null;
		var m = zPeriod;
		var meanS = sumS / m;
		var varS = (sumSs / m - meanS * meanS);
		if (varS < 0.0) varS = 0.0;
		var stdS = Math.sqrt(varS);
		if (stdS == 0.0) return 0.0;
		return (s - meanS) / stdS;
	}

	public function update(input:PairSpreadPair):Null<Float> {
		var a = input.a;
		var b = input.b;
		if (!(a > 0.0 && b > 0.0 && Math.isFinite(a) && Math.isFinite(b))) {
			// Bad tick: skip it without disturbing either window.
			return null;
		}
		var x = Math.log(b);
		var y = Math.log(a);
		var wasFull = reg.isFull();
		var old = reg.push({ x: x, y: y });
		if (wasFull) {
			sumX -= old.x;
			sumY -= old.y;
			sumXx -= old.x * old.x;
			sumXy -= old.x * old.y;
		}
		sumX += x;
		sumY += y;
		sumXx += x * x;
		sumXy += x * y;
		var beta = hedgeRatio();
		if (beta == null) return null;
		var spread = y - beta * x;
		return pushSpread(spread);
	}

	public function reset():Void {
		reg = new RingBuffer(betaPeriod);
		sumX = 0.0;
		sumY = 0.0;
		sumXx = 0.0;
		sumXy = 0.0;
		spreads = new RingBuffer(zPeriod);
		sumS = 0.0;
		sumSs = 0.0;
	}

	public function warmupPeriod():Int {
		// beta_period samples to define the hedge ratio (and the first spread),
		// then z_period − 1 more to fill the spread window.
		return betaPeriod + zPeriod - 1;
	}

	public function isReady():Bool return spreads.length == zPeriod;
	public function name():String return "PairSpreadZScore";

	public static function spec():IndicatorSpec {
		return {
			name: "pair_spread_zscore", args: [TSeries, TSeries, TWindow, TWindow], ret: TScalar, minArgs: 4,
			eval: function(h, args) {
				var seriesA = IndicatorCache.seriesArg(args, 0, "close");
				var seriesB = IndicatorCache.seriesArg(args, 1, "close");
				var bp = IndicatorCache.intArg(args, 2, 14);
				var zp = IndicatorCache.intArg(args, 3, 10);
				var key = "pair_spread_zscore:" + seriesA + ":" + seriesB + ":" + bp + ":" + zp;
				return IndicatorCache.evalPair(h, key, seriesA, seriesB, Math.NaN,
					() -> new PairSpreadZScore(bp, zp), (i, a, b) -> (cast i : PairSpreadZScore).update({ a: a, b: b }));
			}
		};
	}
}

@:structInit
class PairSpreadPair {
	public var a:Float;
	public var b:Float;
}

@:structInit
class PairSpreadXY {
	public var x:Float;
	public var y:Float;
}
