package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Rate of Change Ratio × 100 (ROCR100) — ported from wickra-core's `Rocr100`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rocr100.rs).
 *
 * `close / close[period] · 100`: the same ratio as `rocr` rescaled so that an
 * unchanged price reads 100 rather than 1 — `> 100` is an advance, `< 100` a
 * decline. Where the reference price is zero the result is reported as 0.
 * Non-finite inputs are ignored and the last computed value is returned.
 */
class Rocr100 implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Rocr100: period must be > 0";
		this.period = period;
		window = new RingBuffer(period + 1);
		last = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return last;
		window.push(input);
		if (window.length < period + 1) return null;
		var prev = window.oldest(0);
		var rocr = prev == 0.0 ? 0.0 : input / prev * 100.0;
		last = rocr;
		return rocr;
	}

	public function reset():Void {
		window = new RingBuffer(period + 1);
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period + 1;
	public function name():String return "ROCR100";

	public static function spec():IndicatorSpec {
		return {
			name: "rocr100", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 1);
				return IndicatorCache.evalSeries(h, "rocr100:" + series + ":" + p, series, Math.NaN,
					() -> new Rocr100(p), (i, v) -> (cast i : Rocr100).update(v));
			}
		};
	}
}
