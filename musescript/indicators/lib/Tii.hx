package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Trend Intensity Index (TII) — ported from wickra-core's `Tii`
 * (vendor/wickra/crates/wickra-core/src/indicators/tii.rs).
 *
 * M.H. Pee's `[0, 100]` oscillator: what fraction of the recent SMA
 * deviations are positive. With `dev_t = close_t − SMA(close, sma_period)_t`
 * over the most recent `dev_period` deviations:
 *
 * SD_pos = Σ_{dev_i > 0}  dev_i
 * SD_neg = Σ_{dev_i < 0} |dev_i|
 * TII    = 100 · SD_pos / (SD_pos + SD_neg)
 *
 * High readings (> 80) signal a sustained uptrend, low (< 20) a sustained
 * downtrend; a perfectly flat window falls back to the neutral 50. Canonical
 * Pee parameters are `(sma_period = 60, dev_period = 30)`. Warmup is
 * `sma_period + dev_period − 1`.
 */
class Tii implements MuseIndicator<Float, Float> {
	var smaPeriod:Int;
	var devPeriod:Int;
	var sma:Sma;
	/** Rolling window of the most recent `devPeriod` deviations. */
	var window:Array<Float>;
	var sumPos:Float;
	var sumNeg:Float;
	var last:Null<Float>;

	public function new(smaPeriod:Int, devPeriod:Int) {
		if (smaPeriod == 0 || devPeriod == 0) throw "Tii: period must be > 0";
		this.smaPeriod = smaPeriod;
		this.devPeriod = devPeriod;
		sma = new Sma(smaPeriod);
		window = [];
		sumPos = 0.0;
		sumNeg = 0.0;
		last = null;
	}

	/** Current value if available (null before warmup). */
	public function value():Null<Float> return last;

	public function update(input:Float):Null<Float> {
		var smaValue = sma.update(input);
		if (smaValue == null) return null;
		var dev:Float = input - smaValue;

		if (window.length == devPeriod) {
			var old:Float = window.shift();
			if (old > 0.0) sumPos -= old;
			else if (old < 0.0) sumNeg -= -old;
		}
		window.push(dev);
		if (dev > 0.0) sumPos += dev;
		else if (dev < 0.0) sumNeg += -dev;

		if (window.length < devPeriod) return null;

		var denom = sumPos + sumNeg;
		// A perfectly flat window (or accumulator rounding leaving denom
		// slightly negative) falls back to the neutral mid-point; otherwise
		// clamp to [0, 100] against rolling-subtraction float error.
		var tii = denom <= 0.0 ? 50.0 : Math.min(Math.max(100.0 * sumPos / denom, 0.0), 100.0);
		last = tii;
		return tii;
	}

	public function reset():Void {
		sma.reset();
		window = [];
		sumPos = 0.0;
		sumNeg = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return smaPeriod + devPeriod - 1;
	public function isReady():Bool return last != null;
	public function name():String return "TII";

	public static function spec():IndicatorSpec {
		return {
			name: "tii", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var smaP = IndicatorCache.intArg(args, 1, 60);
				var devP = IndicatorCache.intArg(args, 2, 30);
				var key = "tii:" + series + ":" + smaP + ":" + devP;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Tii(smaP, devP), (i, v) -> (cast i : Tii).update(v));
			}
		};
	}
}
