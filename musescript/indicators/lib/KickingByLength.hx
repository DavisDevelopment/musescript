package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Kicking by Length candlestick pattern — the same gapping-marubozu setup
 * as `Kicking`, refined by an extra strength filter: only fires when the
 * *confirming* second bar's range exceeds the first bar's range (the
 * breakout candle is the more dominant of the two, a stronger signal than
 * an equally- or less-forceful confirmation).
 *
 * Output is the same `Kicking` direction when that extra length condition
 * holds, 0.0 otherwise.
 */
class KickingByLength implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var prev:Null<Bar>;

	public function new(tolerance:Float = 0.05) {
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		prev = null;
	}

	public function update(bar:Bar):Null<Float> {
		var out:Null<Float> = if (prev == null) null else compute(prev, bar);
		prev = bar;
		return out;
	}

	function isRedMarubozu(b:Bar):Bool {
		var range = b.high - b.low;
		if (range <= 0.0) return false;
		var tol = tolerance * range;
		return (b.high - b.open) <= tol && (b.close - b.low) <= tol && b.close < b.open;
	}

	function isGreenMarubozu(b:Bar):Bool {
		var range = b.high - b.low;
		if (range <= 0.0) return false;
		var tol = tolerance * range;
		return (b.high - b.close) <= tol && (b.open - b.low) <= tol && b.close > b.open;
	}

	function compute(bar1:Bar, bar2:Bar):Float {
		var range1 = bar1.high - bar1.low;
		var range2 = bar2.high - bar2.low;
		var bar2Longer = range2 > range1;

		if (isRedMarubozu(bar1) && isGreenMarubozu(bar2) && bar2.low > bar1.high && bar2Longer) return 1.0;
		if (isGreenMarubozu(bar1) && isRedMarubozu(bar2) && bar2.high < bar1.low && bar2Longer) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "KickingByLength";

	public static function spec():IndicatorSpec {
		return {
			name: "kicking_by_length", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "kicking_by_length:" + tol, Math.NaN,
					() -> new KickingByLength(tol), (i, b) -> (cast i : KickingByLength).update(b));
			}
		};
	}
}
