package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Gap Side-by-Side White Lines candlestick pattern — a 3-bar continuation
 * signal: a trend bar gaps, then two consecutive green ("white") bars with
 * similar opens and sizes follow at the gapped level, confirming the gap
 * will hold rather than fill.
 *
 * tol = tolerance * bar1's body size
 *
 * bullish (+1.0) when:
 *  - bar1 green with a real body.
 *  - bar2 gaps up from bar1 (bar2.low > bar1.close), is green.
 *  - bar3 is also green, opens within `tol` of bar2's open, and has a
 *    similar body size to bar2 (within `tol`).
 *
 * Output is 0.0 otherwise (including the first two bars).
 */
class GapSideBySideWhite implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;

	public function new(tolerance:Float = 0.1) {
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		prev = null;
		prevPrev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var pp = prevPrev;
		var p = prev;
		prevPrev = prev;
		prev = bar;

		if (pp == null || p == null) return pp == null && p == null ? null : 0.0;
		return compute(pp, p, bar);
	}

	function compute(bar1:Bar, bar2:Bar, bar3:Bar):Float {
		var body1 = bar1.close - bar1.open;
		if (body1 <= 0.0) return 0.0; // bar1 must be green with a real body
		var tol = tolerance * body1;

		var bar2Green = bar2.close > bar2.open;
		var bar3Green = bar3.close > bar3.open;
		if (!bar2Green || !bar3Green) return 0.0;

		var gappedUp = bar2.low > bar1.close;
		var opensMatch = Math.abs(bar3.open - bar2.open) <= tol;
		var bodiesMatch = Math.abs((bar3.close - bar3.open) - (bar2.close - bar2.open)) <= tol;

		if (gappedUp && opensMatch && bodiesMatch) return 1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		prevPrev = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return prev != null && prevPrev != null;
	public function name():String return "GapSideBySideWhite";

	public static function spec():IndicatorSpec {
		return {
			name: "gap_side_by_side_white", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.1) : 0.1;
				return IndicatorCache.evalBar(h, "gap_side_by_side_white:" + tol, Math.NaN,
					() -> new GapSideBySideWhite(tol), (i, b) -> (cast i : GapSideBySideWhite).update(b));
			}
		};
	}
}
