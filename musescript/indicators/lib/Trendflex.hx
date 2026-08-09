package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.SuperSmoother;
import musescript.types.MuseType;

/**
 * Ehlers' Trendflex — ported from wickra-core's `Trendflex`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/trendflex.rs).
 *
 * The trend-sensitive companion to `Reflex` (John Ehlers, "Reflex: A New
 * Zero-Lag Indicator", *Stocks & Commodities*, Feb 2020): averages how far
 * the SuperSmoothed price sits above or below its values over the lookback,
 * then self-normalises with an adaptive mean-square so output stays near a
 * ±3 band. Stays pinned to one side of zero in a trend, oscillates through
 * zero in a range. First value after `period + 1` SuperSmoothed samples.
 * Series input (f64): `trendflex(close, period)`.
 */
class Trendflex implements MuseIndicator<Float, Float> {
	var period:Int;
	var smoother:SuperSmoother;
	var filt:RingBuffer<Float>;
	var ms:Float;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Trendflex: period must be > 0";
		this.period = period;
		smoother = new SuperSmoother(period);
		filt = new RingBuffer(period + 1);
		ms = 0.0;
		last = null;
	}

	/** Configured lookback period. */
	public function getPeriod():Int return period;

	/** Current value if available. */
	public function value():Null<Float> return last;

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return last;
		var filtVal = smoother.update(price);
		if (filtVal == null) return null;
		filt.push(filtVal);
		if (filt.length < period + 1) return null;

		// Newest at at(0), oldest at oldest(0) / at(period).
		var newest = filt.at(0);
		var sum = 0.0;
		for (i in 1...(period + 1)) {
			sum += newest - filt.at(i);
		}
		sum /= period;
		ms = 0.04 * sum * sum + 0.96 * ms;
		var trendflex = if (ms > 0.0) {
			sum / Math.sqrt(ms);
		} else {
			0.0;
		};
		last = trendflex;
		return trendflex;
	}

	public function reset():Void {
		smoother.reset();
		filt = new RingBuffer(period + 1);
		ms = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return last != null;
	public function name():String return "Trendflex";

	public static function spec():IndicatorSpec {
		return {
			name: "trendflex", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 20);
				return IndicatorCache.evalSeries(h, "trendflex:" + series + ":" + p, series, Math.NaN,
					() -> new Trendflex(p), (i, v) -> (cast i : Trendflex).update(v));
			}
		};
	}
}
