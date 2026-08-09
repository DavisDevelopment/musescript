package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Frying Pan Bottom — ported from wickra-core's `FryPanBottom`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/fry_pan_bottom.rs).
 *
 * A rounded bottom (U) confirmed by recovery. Over the last `period` closes:
 * the minimum close sits in the middle third of the window (the "bowl"), and
 * the latest close is above the first close (the rim is recovered).
 * Output is +1.0 when both hold, 0.0 otherwise.
 */
class FryPanBottom implements MuseIndicator<Bar, Float> {
	var period:Int;
	var closes:RingBuffer<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period < 5) throw "FryPanBottom: period must be >= 5";
		this.period = period;
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		closes.push(bar.close);
		if (closes.length < period) return null;

		var first = closes.oldest(0);
		var last_close = closes.oldest(closes.length - 1);

		// Find the minimum close and its index.
		var min_idx = 0;
		var min_val = Math.POSITIVE_INFINITY;
		for (i in 0...closes.length) {
			var v = closes.oldest(i);
			if (v < min_val) {
				min_val = v;
				min_idx = i;
			}
		}

		// Check if minimum is in the middle third of the window.
		var lo = Math.floor(period / 4);
		var hi = period - Math.floor(period / 4);
		var bowl = min_idx >= lo && min_idx < hi;
		var recovered = last_close > first && last_close > min_val;

		var v = (bowl && recovered) ? 1.0 : 0.0;
		this.last = v;
		return v;
	}

	public function reset():Void {
		closes = new RingBuffer(period);
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "FryPanBottom";

	public static function spec():IndicatorSpec {
		return {
			name: "fry_pan_bottom", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 9);
				return IndicatorCache.evalBar(h, "fry_pan_bottom:" + p, Math.NaN,
					() -> new FryPanBottom(p), (i, b) -> (cast i : FryPanBottom).update(b));
			}
		};
	}
}
