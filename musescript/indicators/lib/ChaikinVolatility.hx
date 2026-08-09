package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Chaikin Volatility: the rate of change, over `rocPeriod` bars, of an EMA
 * of the bar's high-low range.
 *
 * range_t   = high_t - low_t
 * smoothed  = EMA(range, emaPeriod)
 * CV        = (smoothed_t - smoothed_{t-rocPeriod}) / smoothed_{t-rocPeriod} * 100
 *
 * Rising CV means the (smoothed) trading range is widening — volatility
 * expansion; falling means it's contracting.
 */
class ChaikinVolatility implements MuseIndicator<Bar, Float> {
	var ema:Ema;
	var rocPeriod:Int;
	var history:RingBuffer<Float>;

	public function new(emaPeriod:Int, rocPeriod:Int) {
		if (rocPeriod <= 0) throw "ChaikinVolatility: rocPeriod must be > 0";
		ema = new Ema(emaPeriod);
		this.rocPeriod = rocPeriod;
		history = new RingBuffer(rocPeriod + 1);
	}

	public function update(bar:Bar):Null<Float> {
		var smoothed = ema.update(bar.high - bar.low);
		if (smoothed == null) return null;

		history.push(smoothed);
		if (history.length <= rocPeriod) return null;

		var past = history.oldest(0);
		if (past == 0.0) return 0.0;
		return (smoothed - past) / past * 100.0;
	}

	public function reset():Void {
		ema.reset();
		history = new RingBuffer(rocPeriod + 1);
	}

	public function warmupPeriod():Int return ema.period + rocPeriod;
	public function isReady():Bool return history.length > rocPeriod;
	public function name():String return "ChaikinVolatility";

	public static function spec():IndicatorSpec {
		return {
			name: "chaikin_volatility", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var emaPeriod = IndicatorCache.intArg(args, 0, 10);
				var rocPeriod = IndicatorCache.intArg(args, 1, 10);
				var key = "chaikin_volatility:" + emaPeriod + ":" + rocPeriod;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new ChaikinVolatility(emaPeriod, rocPeriod), (i, b) -> (cast i : ChaikinVolatility).update(b));
			}
		};
	}
}
