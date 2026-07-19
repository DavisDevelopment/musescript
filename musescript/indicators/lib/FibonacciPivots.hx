package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Fibonacci Pivots output: pivot plus 3 resistance / 3 support levels. */
typedef FibonacciPivotsOutput = {
	var r3:Float;
	var r2:Float;
	var r1:Float;
	var pivot:Float;
	var s1:Float;
	var s2:Float;
	var s3:Float;
}

/**
 * Fibonacci Pivots: the classic (H+L+C)/3 pivot, with support/resistance
 * offsets scaled by Fibonacci ratios of the prior bar's range instead of the
 * classic-pivot geometric construction. Derived from the *previous
 * completed* bar.
 *
 * pivot = (H + L + C) / 3,  range = H - L
 * R1 = pivot + 0.382*range   S1 = pivot - 0.382*range
 * R2 = pivot + 0.618*range   S2 = pivot - 0.618*range
 * R3 = pivot + 1.000*range   S3 = pivot - 1.000*range
 *
 * One-bar lagged, non-repainting.
 */
class FibonacciPivots implements MuseIndicator<Bar, FibonacciPivotsOutput> {
	var prev:Null<Bar>;

	public function new() {
		prev = null;
	}

	public function update(bar:Bar):Null<FibonacciPivotsOutput> {
		var out = if (prev == null) null else compute(prev);
		prev = bar;
		return out;
	}

	static function compute(bar:Bar):FibonacciPivotsOutput {
		var pivot = (bar.high + bar.low + bar.close) / 3.0;
		var range = bar.high - bar.low;
		return {
			r3: pivot + range,
			r2: pivot + 0.618 * range,
			r1: pivot + 0.382 * range,
			pivot: pivot,
			s1: pivot - 0.382 * range,
			s2: pivot - 0.618 * range,
			s3: pivot - range
		};
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "FibonacciPivots";

	public static function spec():IndicatorSpec {
		return {
			name: "fibonacci_pivots", args: [], ret: TObject([
				{name: "r3", ty: TScalar}, {name: "r2", ty: TScalar}, {name: "r1", ty: TScalar},
				{name: "pivot", ty: TScalar},
				{name: "s1", ty: TScalar}, {name: "s2", ty: TScalar}, {name: "s3", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { r3: Math.NaN, r2: Math.NaN, r1: Math.NaN, pivot: Math.NaN, s1: Math.NaN, s2: Math.NaN, s3: Math.NaN };
				return IndicatorCache.evalBar(h, "fibonacci_pivots", nanFill,
					() -> new FibonacciPivots(), (i, b) -> (cast i : FibonacciPivots).update(b));
			}
		};
	}
}
