package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Classic floor-pivot output: pivot plus 3 resistance / 3 support levels. */
typedef ClassicPivotsOutput = {
	var r3:Float;
	var r2:Float;
	var r1:Float;
	var pivot:Float;
	var s1:Float;
	var s2:Float;
	var s3:Float;
}

/**
 * Classic floor-trader pivots, derived from the *previous completed* bar's
 * high/low/close — the standard textbook formula.
 *
 * pivot = (H + L + C) / 3
 * R1 = 2*pivot - L      S1 = 2*pivot - H
 * R2 = pivot + (H - L)  S2 = pivot - (H - L)
 * R3 = H + 2*(pivot - L)  S3 = L - 2*(H - pivot)
 *
 * One-bar-lagged, non-repainting: the level set from the bar that just
 * closed holds until the next bar closes.
 */
class ClassicPivots implements MuseIndicator<Bar, ClassicPivotsOutput> {
	var prev:Null<Bar>;

	public function new() {
		prev = null;
	}

	public function update(bar:Bar):Null<ClassicPivotsOutput> {
		var out = if (prev == null) null else compute(prev);
		prev = bar;
		return out;
	}

	static function compute(bar:Bar):ClassicPivotsOutput {
		var pivot = (bar.high + bar.low + bar.close) / 3.0;
		var range = bar.high - bar.low;
		return {
			r3: bar.high + 2.0 * (pivot - bar.low),
			r2: pivot + range,
			r1: 2.0 * pivot - bar.low,
			pivot: pivot,
			s1: 2.0 * pivot - bar.high,
			s2: pivot - range,
			s3: bar.low - 2.0 * (bar.high - pivot)
		};
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "ClassicPivots";

	public static function spec():IndicatorSpec {
		return {
			name: "classic_pivots", args: [], ret: TObject([
				{name: "r3", ty: TScalar}, {name: "r2", ty: TScalar}, {name: "r1", ty: TScalar},
				{name: "pivot", ty: TScalar},
				{name: "s1", ty: TScalar}, {name: "s2", ty: TScalar}, {name: "s3", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { r3: Math.NaN, r2: Math.NaN, r1: Math.NaN, pivot: Math.NaN, s1: Math.NaN, s2: Math.NaN, s3: Math.NaN };
				return IndicatorCache.evalBar(h, "classic_pivots", nanFill,
					() -> new ClassicPivots(), (i, b) -> (cast i : ClassicPivots).update(b));
			}
		};
	}
}
