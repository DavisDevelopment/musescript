package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Williams %R — ported from wickra-core's `WilliamsR`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/williams_r.rs).
 *
 * `-100 * (HH - close) / (HH - LL)` over the lookback window; values lie in
 * [-100, 0]. A zero-range window (HH == LL) returns the neutral mid-range
 * value -50 rather than dividing by zero.
 */
class WilliamsR implements MuseIndicator<Bar, Float> {
	var period:Int;
	var highs:Array<Float>;
	var lows:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "WilliamsR: period must be > 0";
		this.period = period;
		highs = [];
		lows = [];
	}

	public function update(bar:Bar):Null<Float> {
		highs.push(bar.high);
		lows.push(bar.low);
		if (highs.length > period) {
			highs.shift();
			lows.shift();
		}
		if (highs.length < period) return null;
		var hh = Math.NEGATIVE_INFINITY, ll = Math.POSITIVE_INFINITY;
		for (h in highs) if (h > hh) hh = h;
		for (l in lows) if (l < ll) ll = l;
		var range = hh - ll;
		if (range == 0) return -50.0;
		return -100.0 * (hh - bar.close) / range;
	}

	public function reset():Void {
		highs = [];
		lows = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return highs.length == period;
	public function name():String return "WilliamsR";

	public static function spec():IndicatorSpec {
		return {
			name: "williams_r", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "williams_r:" + p, Math.NaN,
					() -> new WilliamsR(p), (i, b) -> (cast i : WilliamsR).update(b));
			}
		};
	}
}
