package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Williams Accumulation/Distribution — ported from wickra-core's `Wad`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/wad.rs).
 *
 *   if close > prev_close:  AD = close - min(low,  prev_close)   (true low)
 *   if close < prev_close:  AD = close - max(high, prev_close)   (true high)
 *   if close = prev_close:  AD = 0
 *   WAD_t = WAD_{t-1} + AD
 *
 * Larry Williams' price-only cumulative line (no volume at all). The first
 * candle seeds the reference close and emits nothing; thereafter every bar
 * emits the running total.
 */
class Wad implements MuseIndicator<Bar, Float> {
	var prevClose:Null<Float>;
	var line:Float;
	var last:Null<Float>;

	public function new() {
		reset();
	}

	/** Current value if available (null during warmup). */
	public function value():Null<Float> return last;

	public function update(bar:Bar):Null<Float> {
		if (prevClose == null) {
			prevClose = bar.close;
			return null;
		}
		var prev:Float = prevClose;
		var ad = if (bar.close > prev) {
			bar.close - Math.min(bar.low, prev);
		} else if (bar.close < prev) {
			bar.close - Math.max(bar.high, prev);
		} else {
			0.0;
		};
		line += ad;
		prevClose = bar.close;
		last = line;
		return line;
	}

	public function reset():Void {
		prevClose = null;
		line = 0.0;
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "Wad";

	public static function spec():IndicatorSpec {
		return {
			name: "wad", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "wad", Math.NaN,
				() -> new Wad(), (i, b) -> (cast i : Wad).update(b))
		};
	}
}
