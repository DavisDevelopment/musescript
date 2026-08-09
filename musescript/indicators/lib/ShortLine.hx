package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Short Line candlestick pattern — a single candle whose range is *shorter*
 * than the recent average while its body still dominates that (small) range:
 * a compact directional bar. "Short" only has meaning relative to recent
 * activity, so each candle's range is compared against a rolling average of
 * the previous `period` ranges.
 *
 * avg = mean range of the previous `period` candles
 * short line = range < avg  AND  |close - open| >= 0.5 * range
 * white -> +1.0,  black -> -1.0
 *
 * Output is 0.0 otherwise; the first `period` candles return 0.0 while the
 * rolling average fills. `period` defaults to 5 and must be at least 1.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/short_line.rs
 */
class ShortLine implements MuseIndicator<Bar, Float> {
	var _period:Int;
	var ranges:RingBuffer<Float>;

	public function new(period:Int = 5) {
		if (period <= 0) throw "ShortLine: period must be at least 1";
		this._period = period;
		reset();
	}

	/** Configured averaging period. */
	public function period():Int return _period;

	public function update(candle:Bar):Null<Float> {
		var range = candle.high - candle.low;
		var body = candle.close - candle.open;
		if (!ranges.isFull()) {
			ranges.push(range);
			return 0.0;
		}
		var sum = 0.0;
		for (i in 0...ranges.length) sum += ranges.oldest(i);
		var avg = sum / _period;
		ranges.push(range);
		if (range < avg && Math.abs(body) >= 0.5 * range) {
			return body > 0.0 ? 1.0 : -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		ranges = new RingBuffer(_period);
	}

	public function warmupPeriod():Int return _period;
	public function isReady():Bool return ranges.length >= _period;
	public function name():String return "ShortLine";

	public static function spec():IndicatorSpec {
		return {
			name: "short_line", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = args.length > 0 ? IndicatorCache.intArg(args, 0, 5) : 5;
				return IndicatorCache.evalBar(h, "short_line:" + p, Math.NaN,
					() -> new ShortLine(p), (i, b) -> (cast i : ShortLine).update(b));
			}
		};
	}
}
