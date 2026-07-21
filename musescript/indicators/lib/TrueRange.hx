package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * True Range — ported from wickra-core's `TrueRange`
 * (vendor/wickra/crates/wickra-core/src/indicators/true_range.rs).
 *
 *   TR = max( high − low, |high − close_prev|, |low − close_prev| )
 *
 * The greatest of the bar's own range and the two gaps to the previous
 * close, so it captures volatility that opens between bars rather than only
 * within them. The first bar has no previous close and falls back to
 * `high − low`. Where ATR smooths this series, TrueRange exposes it raw,
 * one value per bar.
 */
class TrueRange implements MuseIndicator<Bar, Float> {
	var prevClose:Null<Float>;
	var hasEmitted:Bool;

	public function new() {
		prevClose = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		var tr = candle.high - candle.low;
		if (prevClose != null) {
			tr = Math.max(tr, Math.max(Math.abs(candle.high - prevClose), Math.abs(candle.low - prevClose)));
		}
		prevClose = candle.close;
		hasEmitted = true;
		return tr;
	}

	public function reset():Void {
		prevClose = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "TrueRange";

	public static function spec():IndicatorSpec {
		return {
			name: "true_range", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "true_range", Math.NaN,
				() -> new TrueRange(), (i, b) -> (cast i : TrueRange).update(b))
		};
	}
}
