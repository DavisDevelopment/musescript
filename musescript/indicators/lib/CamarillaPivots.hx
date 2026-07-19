package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Camarilla Pivots output: the 8 standard resistance/support levels plus the pivot itself. */
typedef CamarillaOutput = {
	var r4:Float;
	var r3:Float;
	var r2:Float;
	var r1:Float;
	var pivot:Float;
	var s1:Float;
	var s2:Float;
	var s3:Float;
	var s4:Float;
}

/**
 * Camarilla Pivots: intraday support/resistance levels derived from the
 * *previous completed* bar's high/low/close, using the standard Camarilla
 * multipliers on the prior range.
 *
 * range = prevHigh - prevLow
 * R4 = close + range * 1.1/2,   R3 = close + range * 1.1/4
 * R2 = close + range * 1.1/6,   R1 = close + range * 1.1/12
 * S1 = close - range * 1.1/12,  S2 = close - range * 1.1/6
 * S3 = close - range * 1.1/4,   S4 = close - range * 1.1/2
 * Pivot = (prevHigh + prevLow + close) / 3
 *
 * All 9 levels are computed from the bar that just closed and held constant
 * until the next bar closes — a one-bar-lagged, non-repainting level set.
 */
class CamarillaPivots implements MuseIndicator<Bar, CamarillaOutput> {
	var prev:Null<Bar>;

	public function new() {
		prev = null;
	}

	public function update(bar:Bar):Null<CamarillaOutput> {
		var out = if (prev == null) null else compute(prev);
		prev = bar;
		return out;
	}

	static function compute(bar:Bar):CamarillaOutput {
		var range = bar.high - bar.low;
		var c = bar.close;
		return {
			r4: c + range * 1.1 / 2.0,
			r3: c + range * 1.1 / 4.0,
			r2: c + range * 1.1 / 6.0,
			r1: c + range * 1.1 / 12.0,
			pivot: (bar.high + bar.low + bar.close) / 3.0,
			s1: c - range * 1.1 / 12.0,
			s2: c - range * 1.1 / 6.0,
			s3: c - range * 1.1 / 4.0,
			s4: c - range * 1.1 / 2.0
		};
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "CamarillaPivots";

	public static function spec():IndicatorSpec {
		return {
			name: "camarilla_pivots", args: [], ret: TObject([
				{name: "r4", ty: TScalar}, {name: "r3", ty: TScalar}, {name: "r2", ty: TScalar}, {name: "r1", ty: TScalar},
				{name: "pivot", ty: TScalar},
				{name: "s1", ty: TScalar}, {name: "s2", ty: TScalar}, {name: "s3", ty: TScalar}, {name: "s4", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { r4: Math.NaN, r3: Math.NaN, r2: Math.NaN, r1: Math.NaN, pivot: Math.NaN, s1: Math.NaN, s2: Math.NaN, s3: Math.NaN, s4: Math.NaN };
				return IndicatorCache.evalBar(h, "camarilla_pivots", nanFill,
					() -> new CamarillaPivots(), (i, b) -> (cast i : CamarillaPivots).update(b));
			}
		};
	}
}
