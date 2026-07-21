package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Volume-Price Trend — ported from wickra-core's `VolumePriceTrend`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/vpt.rs).
 *
 *   VPT_t = VPT_{t-1} + volume_t * (close_t - close_{t-1}) / close_{t-1}
 *
 * A cumulative volume line weighted by percentage price change. The first
 * bar establishes the baseline at 0 (and emits it). A zero previous close
 * contributes 0 rather than NaN.
 */
class Vpt implements MuseIndicator<Bar, Float> {
	var prevClose:Null<Float>;
	var total:Float;
	var hasEmitted:Bool;

	public function new() {
		reset();
	}

	/** Current cumulative value if at least one candle has been ingested. */
	public function value():Null<Float> return hasEmitted ? total : null;

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		if (prevClose == null) {
			// The first candle establishes the baseline at 0.
			prevClose = bar.close;
			return total;
		}
		var prev:Float = prevClose;
		var roc = if (prev == 0.0) {
			// Undefined ratio against a zero previous close.
			0.0;
		} else {
			(bar.close - prev) / prev;
		};
		total += bar.volume * roc;
		prevClose = bar.close;
		return total;
	}

	public function reset():Void {
		prevClose = null;
		total = 0.0;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "VPT";

	public static function spec():IndicatorSpec {
		return {
			name: "vpt", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "vpt", Math.NaN,
				() -> new Vpt(), (i, b) -> (cast i : Vpt).update(b))
		};
	}
}
