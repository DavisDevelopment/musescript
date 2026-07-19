package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rate of Change Ratio (ROCR) — ported from wickra-core's `Rocr`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rocr.rs).
 *
 * The momentum ratio relative to the price `period` bars ago: `close / close[period]`.
 * `1.0` means no change, `> 1` an advance, `< 1` a decline. It is `Rocp` plus one.
 * Where the reference price is zero the result is reported as `0`.
 */
class Rocr implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Rocr: period must be > 0";
		this.period = period;
		this.window = [];
		this.last = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return last;
		}

		if (window.length == period + 1) {
			window.shift();
		}
		window.push(input);

		if (window.length < period + 1) {
			return null;
		}

		var prev = window[0];
		var rocr = if (prev == 0.0) 0.0 else input / prev;
		last = rocr;
		return rocr;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period + 1;
	public function name():String return "ROCR";

	public static function spec():IndicatorSpec {
		return {
			name: "rocr", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 1);
				return IndicatorCache.evalSeries(h, "rocr:" + series + ":" + p, series, Math.NaN,
					() -> new Rocr(p), (i, v) -> (cast i : Rocr).update(v));
			}
		};
	}
}
