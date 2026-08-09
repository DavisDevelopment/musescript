package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Dumpling Top — ported from wickra-core's `DumplingTop`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/dumpling_top.rs).
 *
 * A rounded top (dome) pattern confirmed by a breakdown. Over the last `period`
 * closes, the maximum close sits in the middle third of the window (the "dome")
 * and the latest close is below the first close (the breakdown).
 *
 * ```
 * signal = −1 when both conditions hold, else 0
 * ```
 *
 * The dumpling top is a distribution pattern: price rounds over at the top as
 * buying fades, then rolls down through the level it rose from.
 */
class DumplingTop implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var closes:RingBuffer<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period < 5) throw "DumplingTop: period must be >= 5";
		this.period = period;
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		closes.push(bar.close);

		if (closes.length < period) {
			return null;
		}

		var first = closes.oldest(0);
		var lastClose = closes.oldest(closes.length - 1);

		// Find max and its index
		var maxIdx = 0;
		var maxVal = Math.NEGATIVE_INFINITY;
		for (i in 0...closes.length) {
			var v = closes.oldest(i);
			if (v > maxVal) {
				maxVal = v;
				maxIdx = i;
			}
		}

		// Middle third boundaries: lo = period/4, hi = period - period/4
		var lo = Std.int(period / 4);
		var hi = period - Std.int(period / 4);

		var dome = maxIdx >= lo && maxIdx < hi;
		var brokeDown = lastClose < first && lastClose < maxVal;

		var v = if (dome && brokeDown) -1.0 else 0.0;
		last = v;
		return v;
	}

	public function reset():Void {
		closes = new RingBuffer(period);
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "DumplingTop";

	public static function spec():IndicatorSpec {
		return {
			name: "dumpling_top", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 9);
				return IndicatorCache.evalBar(h, "dumpling_top:" + p, Math.NaN,
					() -> new DumplingTop(p), (i, b) -> (cast i : DumplingTop).update(b));
			}
		};
	}
}
