package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Absolute Price Oscillator — ported from wickra-core's `Apo`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/apo.rs).
 *
 * The raw difference between a fast and a slow EMA. This is MACD's line
 * without the signal-EMA.
 *
 * APO_t = EMA(price, fast)_t − EMA(price, slow)_t
 *
 * Default parameters mirror MACD: (fast = 12, slow = 26). Fast must be
 * strictly less than slow.
 */
class Apo implements MuseIndicator<Float, Float> {
	var fastPeriod:Int;
	var slowPeriod:Int;
	var fast:Ema;
	var slow:Ema;

	public function new(fastPeriod:Int, slowPeriod:Int) {
		if (fastPeriod == 0 || slowPeriod == 0) throw "Apo: periods must be > 0";
		if (fastPeriod >= slowPeriod) throw "Apo: fast period must be strictly less than slow";
		this.fastPeriod = fastPeriod;
		this.slowPeriod = slowPeriod;
		this.fast = new Ema(fastPeriod);
		this.slow = new Ema(slowPeriod);
	}

	public function update(input:Float):Null<Float> {
		// Feed both EMAs on every input so the slow one warms in parallel.
		var f = fast.update(input);
		var s = slow.update(input);
		if (f == null || s == null) return null;
		return f - s;
	}

	public function reset():Void {
		fast.reset();
		slow.reset();
	}

	public function warmupPeriod():Int return slowPeriod;
	public function isReady():Bool return slow.isReady();
	public function name():String return "Apo";

	public static function spec():IndicatorSpec {
		return {
			name: "apo", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var fastP = IndicatorCache.intArg(args, 1, 12);
				var slowP = IndicatorCache.intArg(args, 2, 26);
				var key = "apo:" + series + ":" + fastP + ":" + slowP;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Apo(fastP, slowP), (i, v) -> (cast i : Apo).update(v));
			}
		};
	}
}
