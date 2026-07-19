package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** DeMark Pivots output: pivot plus one resistance / one support level. */
typedef DemarkPivotsOutput = {
	var r1:Float;
	var pivot:Float;
	var s1:Float;
}

/**
 * DeMark Pivots: unlike the classic/Camarilla families, the base value `X`
 * is *conditional* on how the prior bar closed relative to its open —
 * giving the level set a directional bias baked in. Derived from the
 * *previous completed* bar.
 *
 * if close < open:  X = H + 2*L + C
 * if close > open:  X = 2*H + L + C
 * if close == open: X = H + L + 2*C
 *
 * pivot = X / 4
 * R1    = X / 2 - L
 * S1    = X / 2 - H
 *
 * One-bar lagged, non-repainting.
 */
class DemarkPivots implements MuseIndicator<Bar, DemarkPivotsOutput> {
	var prev:Null<Bar>;

	public function new() {
		prev = null;
	}

	public function update(bar:Bar):Null<DemarkPivotsOutput> {
		var out = if (prev == null) null else compute(prev);
		prev = bar;
		return out;
	}

	static function compute(bar:Bar):DemarkPivotsOutput {
		var x = if (bar.close < bar.open) {
			bar.high + 2.0 * bar.low + bar.close;
		} else if (bar.close > bar.open) {
			2.0 * bar.high + bar.low + bar.close;
		} else {
			bar.high + bar.low + 2.0 * bar.close;
		}
		return { r1: x / 2.0 - bar.low, pivot: x / 4.0, s1: x / 2.0 - bar.high };
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "DemarkPivots";

	public static function spec():IndicatorSpec {
		return {
			name: "demark_pivots", args: [], ret: TObject([
				{name: "r1", ty: TScalar}, {name: "pivot", ty: TScalar}, {name: "s1", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { r1: Math.NaN, pivot: Math.NaN, s1: Math.NaN };
				return IndicatorCache.evalBar(h, "demark_pivots", nanFill,
					() -> new DemarkPivots(), (i, b) -> (cast i : DemarkPivots).update(b));
			}
		};
	}
}
