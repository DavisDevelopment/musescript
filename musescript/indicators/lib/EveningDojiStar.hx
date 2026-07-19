package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Evening Doji Star candlestick pattern — a 3-bar bearish reversal: a strong
 * green bar, a gapping doji, then a red bar that closes deep into the first
 * bar's body.
 *
 * tol = tolerance * (bar2.high - bar2.low)
 *
 * bearish (-1.0) when:
 *  - bar1 green with a real body.
 *  - bar2 is a doji (|close-open| <= tol) that gapped up (bar2.low > bar1.close).
 *  - bar3 red, gaps down from bar2 (bar3.high < bar2.low), and closes below
 *    the midpoint of bar1's body (confirms the reversal reached into bar1).
 *
 * Output is 0.0 otherwise (including the first two bars).
 */
class EveningDojiStar implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;

	public function new(tolerance:Float = 0.05) {
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
		var range2 = bar2.high - bar2.low;
		if (range2 <= 0.0) return 0.0;
		var tol = tolerance * range2;
		var bar2IsDoji = Math.abs(bar2.close - bar2.open) <= tol;
		if (!bar2IsDoji) return 0.0;

		var bar1BodyMid = (bar1.open + bar1.close) / 2.0;
		if (bar1.close > bar1.open
			&& bar2.low > bar1.close
			&& bar3.close < bar3.open
			&& bar3.high < bar2.low
			&& bar3.close < bar1BodyMid) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		prevPrev = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return prev != null && prevPrev != null;
	public function name():String return "EveningDojiStar";

	public static function spec():IndicatorSpec {
		return {
			name: "evening_doji_star", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "evening_doji_star:" + tol, Math.NaN,
					() -> new EveningDojiStar(tol), (i, b) -> (cast i : EveningDojiStar).update(b));
			}
		};
	}
}
