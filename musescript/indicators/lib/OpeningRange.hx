package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Opening Range output: the high/low of the very first bar seen. */
typedef OpeningRangeOutput = {
	var high:Float;
	var low:Float;
}

/**
 * Opening Range: the high/low of the *first* bar the indicator ever sees,
 * held fixed forever after — the classic "opening range breakout" reference
 * level, at the single-bar granularity (see `InitialBalance` for the
 * multi-bar analogue).
 */
class OpeningRange implements MuseIndicator<Bar, OpeningRangeOutput> {
	var high:Null<Float>;
	var low:Null<Float>;

	public function new() {
		high = null;
		low = null;
	}

	public function update(bar:Bar):Null<OpeningRangeOutput> {
		if (high == null) {
			high = bar.high;
			low = bar.low;
		}
		return { high: high, low: low };
	}

	public function reset():Void {
		high = null;
		low = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return high != null;
	public function name():String return "OpeningRange";

	public static function spec():IndicatorSpec {
		return {
			name: "opening_range", args: [], ret: TObject([
				{name: "high", ty: TScalar}, {name: "low", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "opening_range", { high: Math.NaN, low: Math.NaN },
				() -> new OpeningRange(), (i, b) -> (cast i : OpeningRange).update(b))
		};
	}
}
