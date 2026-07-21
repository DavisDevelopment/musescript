package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD DeMarker — ported from wickra-core's `TdDeMarker`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_demarker.rs).
 *
 * Bounded [0, 1] oscillator built from highs and lows:
 *   DeMax(i) = max(high[i] - high[i-1], 0)
 *   DeMin(i) = max(low[i-1] - low[i], 0)
 *   DeMarker = SMA(DeMax, period) / (SMA(DeMax, period) + SMA(DeMin, period))
 * A perfectly flat window (both averages zero) emits the neutral midpoint 0.5.
 */
class TdDemarker implements MuseIndicator<Bar, Float> {
	var period:Int;
	var hasPrev:Bool;
	var prevHigh:Float;
	var prevLow:Float;
	var demax:Array<Float>;
	var demin:Array<Float>;
	var lastValue:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "TdDemarker: period must be > 0";
		this.period = period;
		reset();
	}

	/** Configured window. */
	public function getPeriod():Int return period;

	/** Latest emitted value if available. */
	public function value():Null<Float> return lastValue;

	public function update(bar:Bar):Null<Float> {
		if (!hasPrev) {
			hasPrev = true;
			prevHigh = bar.high;
			prevLow = bar.low;
			return null;
		}
		var dmax = Math.max(bar.high - prevHigh, 0.0);
		var dmin = Math.max(prevLow - bar.low, 0.0);
		prevHigh = bar.high;
		prevLow = bar.low;
		if (demax.length == period) {
			demax.shift();
			demin.shift();
		}
		demax.push(dmax);
		demin.push(dmin);
		if (demax.length < period) return null;
		var sumMax = 0.0, sumMin = 0.0;
		for (v in demax) sumMax += v;
		for (v in demin) sumMin += v;
		var n:Float = period;
		sumMax /= n;
		sumMin /= n;
		var denom = sumMax + sumMin;
		var v = denom == 0.0 ? 0.5 : sumMax / denom;
		lastValue = v;
		return v;
	}

	public function reset():Void {
		hasPrev = false;
		prevHigh = 0.0;
		prevLow = 0.0;
		demax = [];
		demin = [];
		lastValue = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return lastValue != null;
	public function name():String return "TDDeMarker";

	public static function spec():IndicatorSpec {
		return {
			name: "td_demarker", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "td_demarker:" + p, Math.NaN,
					() -> new TdDemarker(p), (i, b) -> (cast i : TdDemarker).update(b));
			}
		};
	}
}
