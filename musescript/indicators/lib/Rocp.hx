package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rate of Change Percentage (ROCP) — ported from wickra-core's `Rocp`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rocp.rs).
 *
 * The momentum measure `(close - close[period]) / close[period]` expressed as
 * a raw fraction rather than a percentage. Where the reference price is zero
 * the result is reported as `0`.
 */
class Rocp implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Rocp: period must be > 0";
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
		var rocp = if (prev == 0.0) 0.0 else (input - prev) / prev;
		last = rocp;
		return rocp;
	}

	public function reset():Void {
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return window.length == period + 1;
	public function name():String return "ROCP";

	public static function spec():IndicatorSpec {
		return {
			name: "rocp", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 1);
				return IndicatorCache.evalSeries(h, "rocp:" + series + ":" + p, series, Math.NaN,
					() -> new Rocp(p), (i, v) -> (cast i : Rocp).update(v));
			}
		};
	}
}
