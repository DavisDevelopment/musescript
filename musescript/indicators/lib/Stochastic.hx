package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/** Stochastic Oscillator output. */
typedef StochasticOutput = {
	/** Raw %K: 100 · (close − LL) / (HH − LL) over the lookback. */
	var k:Float;
	/** %D: SMA of %K over the smoothing period. */
	var d:Float;
}

/**
 * Fast Stochastic Oscillator (%K and %D) — ported from wickra-core's
 * `Stochastic`
 * (vendor/wickra/crates/wickra-core/src/indicators/stochastic.rs).
 *
 * %K reports where the close sits inside the highest-high / lowest-low range
 * of the trailing `kPeriod` bars; %D is an SMA of %K over `dPeriod`. A flat
 * range (HH == LL) reports the neutral 50 by convention. Upstream keeps the
 * rolling extremes in monotonic deques for O(1) amortized updates; this port
 * scans the fixed-size window instead — identical outputs, and the window is
 * chart-period sized.
 *
 * NOTE: registered as "stochastic" — MuseScript core's legacy "stoch" builtin
 * is a different implementation and is deliberately left untouched.
 */
class Stochastic implements MuseIndicator<Bar, StochasticOutput> {
	var kPeriod:Int;
	var dPeriod:Int;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;
	var dSma:Sma;
	var lastK:Null<Float>;

	public function new(kPeriod:Int, dPeriod:Int) {
		if (kPeriod <= 0 || dPeriod <= 0) throw "Stochastic: periods must be > 0";
		this.kPeriod = kPeriod;
		this.dPeriod = dPeriod;
		highs = new RingBuffer(kPeriod);
		lows = new RingBuffer(kPeriod);
		dSma = new Sma(dPeriod);
		lastK = null;
	}

	/** Classic fast stochastic: %K = 14, %D = 3. */
	public static function classic():Stochastic {
		return new Stochastic(14, 3);
	}

	public function update(bar:Bar):Null<StochasticOutput> {
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length < kPeriod) return null;

		var hh = highs.at(0);
		for (i in 0...highs.length) {
			var v = highs.at(i);
			if (v > hh) hh = v;
		}
		var ll = lows.at(0);
		for (i in 0...lows.length) {
			var v = lows.at(i);
			if (v < ll) ll = v;
		}
		var range = hh - ll;
		// Flat range; convention: 50 (neutral, like RSI on flat input).
		var k = range == 0.0 ? 50.0 : 100.0 * (bar.close - ll) / range;
		lastK = k;
		var d = dSma.update(k);
		if (d == null) return null;
		return {k: k, d: d};
	}

	public function reset():Void {
		highs = new RingBuffer(kPeriod);
		lows = new RingBuffer(kPeriod);
		dSma.reset();
		lastK = null;
	}

	public function warmupPeriod():Int return kPeriod + dPeriod - 1;
	public function isReady():Bool return dSma.isReady();
	public function name():String return "Stochastic";

	public static function spec():IndicatorSpec {
		return {
			name: "stochastic", args: [TWindow, TWindow], ret: TObject([
				{name: "k", ty: TScalar}, {name: "d", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var kp = IndicatorCache.intArg(args, 0, 14);
				var dp = IndicatorCache.intArg(args, 1, 3);
				var key = "stochastic:" + kp + ":" + dp;
				return IndicatorCache.evalBar(h, key, {k: Math.NaN, d: Math.NaN},
					() -> new Stochastic(kp, dp), (i, b) -> (cast i : Stochastic).update(b));
			}
		};
	}
}
