package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Close vs Open: the bar's return expressed as a percentage of the open.
 *
 * CloseVsOpen = (close - open) / open * 100
 *
 * A stateless per-bar transform; positive means the bar closed green,
 * negative red. Falls back to 0 on a zero-open bar (undefined percentage).
 */
class CloseVsOpen implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(bar:Bar):Null<Float> {
		hasEmitted = true;
		if (bar.open == 0.0) return 0.0;
		return (bar.close - bar.open) / bar.open * 100.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "CloseVsOpen";

	public static function spec():IndicatorSpec {
		return {
			name: "close_vs_open", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "close_vs_open", Math.NaN,
				() -> new CloseVsOpen(), (i, b) -> (cast i : CloseVsOpen).update(b))
		};
	}
}
