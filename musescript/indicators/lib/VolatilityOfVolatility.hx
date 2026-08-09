package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Volatility of Volatility — ported from wickra-core's `VolatilityOfVolatility`
 * (vendor/wickra/crates/wickra-core/src/indicators/volatility_of_volatility.rs).
 *
 * Two-stage estimator of how unstable the volatility regime is:
 *
 * r_t   = ln(price_t / price_{t−1})
 * vol_t = stddev_sample(r over vol_window)     (rolling realized volatility)
 * VoV   = stddev_sample(vol over vov_window)   (dispersion of that series)
 *
 * Both stages use the unbiased `n − 1` sample standard deviation; O(1) per
 * update. Non-finite and non-positive prices are ignored (the log return
 * would be undefined): the tick is dropped, state is untouched, and the
 * last value is returned. Warmup is `vol_window + vov_window`.
 */
class VolatilityOfVolatility implements MuseIndicator<Float, Float> {
	var volWindow:Int;
	var vovWindow:Int;
	var prevPrice:Null<Float>;
	var returns:RingBuffer<Float>;
	var retSum:Float;
	var retSumSq:Float;
	var vols:RingBuffer<Float>;
	var volSum:Float;
	var volSumSq:Float;
	var last:Null<Float>;

	public function new(volWindow:Int, vovWindow:Int) {
		if (volWindow == 0 || vovWindow == 0) throw "VolatilityOfVolatility: period must be > 0";
		if (volWindow < 2 || vovWindow < 2) throw "VolatilityOfVolatility: vol-of-vol windows must both be >= 2";
		this.volWindow = volWindow;
		this.vovWindow = vovWindow;
		reset();
	}

	/** Sample stddev from running (sum, sum of squares, count); Bessel's `n − 1`. */
	static function sampleStddev(sum:Float, sumSq:Float, count:Int):Float {
		var n = count;
		var mean = sum / n;
		var variance = (sumSq - n * mean * mean) / (n - 1);
		if (variance < 0.0) variance = 0.0;
		return Math.sqrt(variance);
	}

	/** Current value if available (null before warmup). */
	public function value():Null<Float> return last;

	public function update(input:Float):Null<Float> {
		// Non-finite / non-positive prices are skipped: ln(input / prev) is
		// undefined, so the tick must not enter the return window.
		if (!Math.isFinite(input) || input <= 0.0) return last;
		if (prevPrice == null) {
			prevPrice = input;
			return null;
		}
		var prev:Float = prevPrice;
		prevPrice = input;
		var r = Math.log(input / prev);

		// Stage one: rolling sample volatility of log returns.
		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var retFull = returns.isFull();
		var oldRet = returns.push(r);
		if (retFull) {
			retSum -= oldRet;
			retSumSq -= oldRet * oldRet;
		}
		retSum += r;
		retSumSq += r * r;
		if (returns.length < volWindow) return null;
		var vol = sampleStddev(retSum, retSumSq, volWindow);

		// Stage two: rolling sample dispersion of the volatility series.
		var volFull = vols.isFull();
		var oldVol = vols.push(vol);
		if (volFull) {
			volSum -= oldVol;
			volSumSq -= oldVol * oldVol;
		}
		volSum += vol;
		volSumSq += vol * vol;
		if (vols.length < vovWindow) return null;
		var vov = sampleStddev(volSum, volSumSq, vovWindow);
		last = vov;
		return vov;
	}

	public function reset():Void {
		prevPrice = null;
		returns = new RingBuffer(volWindow);
		retSum = 0.0;
		retSumSq = 0.0;
		vols = new RingBuffer(vovWindow);
		volSum = 0.0;
		volSumSq = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return volWindow + vovWindow;
	public function isReady():Bool return last != null;
	public function name():String return "VolatilityOfVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "volatility_of_volatility", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var volW = IndicatorCache.intArg(args, 1, 20);
				var vovW = IndicatorCache.intArg(args, 2, 20);
				var key = "volatility_of_volatility:" + series + ":" + volW + ":" + vovW;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new VolatilityOfVolatility(volW, vovW), (i, v) -> (cast i : VolatilityOfVolatility).update(v));
			}
		};
	}
}
