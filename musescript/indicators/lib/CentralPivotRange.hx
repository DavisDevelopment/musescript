package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Central Pivot Range output: pivot plus its top/bottom band. */
typedef CentralPivotRangeOutput = {
	var top:Float;
	var pivot:Float;
	var bottom:Float;
}

/**
 * Central Pivot Range (CPR): a three-line variant of the classic pivot that
 * frames the pivot in a symmetric band, derived from the *previous
 * completed* bar's high/low/close.
 *
 * pivot  = (H + L + C) / 3
 * bottom = (H + L) / 2
 * top    = 2*pivot - bottom          (pivot reflected across bottom)
 *
 * A wide CPR (top far from bottom) suggests a choppier prior session; a
 * narrow CPR suggests a tight, more directional one. One-bar lagged,
 * non-repainting.
 */
class CentralPivotRange implements MuseIndicator<Bar, CentralPivotRangeOutput> {
	var prev:Null<Bar>;

	public function new() {
		prev = null;
	}

	public function update(bar:Bar):Null<CentralPivotRangeOutput> {
		var out = if (prev == null) null else compute(prev);
		prev = bar;
		return out;
	}

	static function compute(bar:Bar):CentralPivotRangeOutput {
		var pivot = (bar.high + bar.low + bar.close) / 3.0;
		var bottom = (bar.high + bar.low) / 2.0;
		var top = 2.0 * pivot - bottom;
		return { top: top, pivot: pivot, bottom: bottom };
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "CentralPivotRange";

	public static function spec():IndicatorSpec {
		return {
			name: "central_pivot_range", args: [], ret: TObject([
				{name: "top", ty: TScalar}, {name: "pivot", ty: TScalar}, {name: "bottom", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { top: Math.NaN, pivot: Math.NaN, bottom: Math.NaN };
				return IndicatorCache.evalBar(h, "central_pivot_range", nanFill,
					() -> new CentralPivotRange(), (i, b) -> (cast i : CentralPivotRange).update(b));
			}
		};
	}
}
