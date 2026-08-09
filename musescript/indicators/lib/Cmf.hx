package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Chaikin Money Flow: money-flow volume summed over a trailing window of
 * `period` bars, normalized by total volume in the same window.
 *
 * MFM_t = ((close_t - low_t) - (high_t - close_t)) / (high_t - low_t)   (-1..+1, 0 on a zero-range bar)
 * MFV_t = MFM_t * volume_t
 * CMF   = sum(MFV over period) / sum(volume over period)
 *
 * Unlike the cumulative ADL, CMF is a bounded oscillator (-1..+1) since it's
 * volume-normalized over a fixed window rather than accumulated forever.
 */
class Cmf implements MuseIndicator<Bar, Float> {
	var period:Int;
	var mfvWindow:RingBuffer<Float>;
	var volWindow:RingBuffer<Float>;
	var sumMfv:Float;
	var sumVol:Float;

	public function new(period:Int) {
		if (period <= 0) throw "Cmf: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		var range = bar.high - bar.low;
		var mfv = if (range == 0.0) 0.0 else {
			var mfm = ((bar.close - bar.low) - (bar.high - bar.close)) / range;
			mfm * bar.volume;
		}

		var wasFull = mfvWindow.isFull();
		var oldMfv = mfvWindow.push(mfv);
		var oldVol = volWindow.push(bar.volume);
		if (wasFull) {
			sumMfv -= oldMfv;
			sumVol -= oldVol;
		}
		sumMfv += mfv;
		sumVol += bar.volume;

		if (mfvWindow.length < period) return null;
		if (sumVol == 0.0) return 0.0;
		return sumMfv / sumVol;
	}

	public function reset():Void {
		mfvWindow = new RingBuffer(period);
		volWindow = new RingBuffer(period);
		sumMfv = 0.0;
		sumVol = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return mfvWindow.length == period;
	public function name():String return "Cmf";

	public static function spec():IndicatorSpec {
		return {
			name: "cmf", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "cmf:" + p, Math.NaN,
					() -> new Cmf(p), (i, b) -> (cast i : Cmf).update(b));
			}
		};
	}
}
