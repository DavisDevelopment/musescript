package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.SuperSmoother;
import musescript.types.MuseType;

/**
 * Reflex — ported from wickra-core's `Reflex`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/reflex.rs).
 *
 * Ehlers' zero-lag cycle oscillator. Measures deviation of smoothed price from
 * the straight line connecting window endpoints. Adaptive normalizer rescales output
 * to roughly ±3 range regardless of price. First value lands after period+1 SuperSmoothed samples.
 */
class Reflex implements MuseIndicator<Float, Float> {
	var period:Int;
	var smoother:SuperSmoother;
	var filt:Array<Float>;
	var ms:Float;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Reflex: period must be > 0";
		this.period = period;
		smoother = new SuperSmoother(period);
		filt = [];
		ms = 0.0;
		last = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) {
			return last;
		}

		var filtVal = smoother.update(price);
		if (filtVal == null) {
			return null;
		}

		// Maintain filt window of size period + 1
		if (filt.length == period + 1) {
			filt.shift();
		}
		filt.push(filtVal);

		if (filt.length < period + 1) {
			return null;
		}

		// Newest at index period, oldest at index 0
		var newest = filt[period];
		var oldest = filt[0];
		var slope = (oldest - newest) / period;

		var sum = 0.0;
		for (i in 1...(period + 1)) {
			sum += (newest + i * slope) - filt[period - i];
		}
		sum /= period;

		ms = 0.04 * sum * sum + 0.96 * ms;

		var reflex = if (ms > 0.0) {
			sum / Math.sqrt(ms);
		} else {
			0.0;
		};

		last = reflex;
		return reflex;
	}

	public function reset():Void {
		smoother.reset();
		filt = [];
		ms = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "Reflex";

	public static function spec():IndicatorSpec {
		return {
			name: "reflex", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "reflex:" + series + ":" + p, series, Math.NaN,
					() -> new Reflex(p), (i, v) -> (cast i : Reflex).update(v));
			}
		};
	}
}
