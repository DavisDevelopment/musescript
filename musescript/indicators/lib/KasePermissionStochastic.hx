package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/** Kase Permission Stochastic output: a fast and a slow line. */
typedef KasePermissionStochasticOutput = {
	/** Fast line: EMA of the raw %K over the smoothing period. */
	var fast:Float;
	/** Slow line: EMA of the fast line over the smoothing period. */
	var slow:Float;
}

/**
 * Kase Permission Stochastic — ported from wickra-core's
 * `KasePermissionStochastic`
 * (vendor/wickra/crates/wickra-core/src/indicators/kase_permission_stochastic.rs).
 *
 * A stochastic oscillator smoothed twice, whose fast/slow relationship grants
 * or denies "permission" to trade with a higher-timeframe signal:
 *
 *   raw%K = 100 · (close − LL) / (HH − LL)   over `length` (50 when HH == LL)
 *   fast  = EMA(raw%K, smooth)
 *   slow  = EMA(fast,  smooth)
 *
 * Reference: Cynthia Kase, "Trading with the Odds", 1996. Classic parameters
 * are length = 9, smooth = 3.
 */
class KasePermissionStochastic implements MuseIndicator<Bar, KasePermissionStochasticOutput> {
	var length:Int;
	var smooth:Int;
	var highs:Array<Float>;
	var lows:Array<Float>;
	var fastEma:Ema;
	var slowEma:Ema;

	public function new(length:Int, smooth:Int) {
		if (length <= 0) throw "KasePermissionStochastic: length must be > 0";
		this.length = length;
		this.smooth = smooth;
		highs = [];
		lows = [];
		fastEma = new Ema(smooth);
		slowEma = new Ema(smooth);
	}

	/** Cynthia Kase's classic parameters: length = 9, smooth = 3. */
	public static function classic():KasePermissionStochastic {
		return new KasePermissionStochastic(9, 3);
	}

	public function update(bar:Bar):Null<KasePermissionStochasticOutput> {
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length > length) {
			highs.shift();
			lows.shift();
		}
		if (highs.length < length) return null;

		var highest = highs[0];
		for (v in highs) if (v > highest) highest = v;
		var lowest = lows[0];
		for (v in lows) if (v < lowest) lowest = v;
		var rawK = highest > lowest ? 100.0 * (bar.close - lowest) / (highest - lowest) : 50.0;

		var fast = fastEma.update(rawK);
		if (fast == null) return null;
		var slow = slowEma.update(fast);
		if (slow == null) return null;
		return {fast: fast, slow: slow};
	}

	public function reset():Void {
		highs = [];
		lows = [];
		fastEma.reset();
		slowEma.reset();
	}

	public function warmupPeriod():Int {
		// raw%K ready after `length` bars; each EMA seeds over `smooth` values.
		return length + 2 * smooth - 2;
	}

	public function isReady():Bool return slowEma.isReady();
	public function name():String return "KasePermissionStochastic";

	public static function spec():IndicatorSpec {
		return {
			name: "kase_permission_stochastic", args: [TWindow, TWindow], ret: TObject([
				{name: "fast", ty: TScalar}, {name: "slow", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var l = IndicatorCache.intArg(args, 0, 9);
				var s = IndicatorCache.intArg(args, 1, 3);
				var key = "kase_permission_stochastic:" + l + ":" + s;
				return IndicatorCache.evalBar(h, key, {fast: Math.NaN, slow: Math.NaN},
					() -> new KasePermissionStochastic(l, s),
					(i, b) -> (cast i : KasePermissionStochastic).update(b));
			}
		};
	}
}
