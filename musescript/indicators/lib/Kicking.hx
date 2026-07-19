package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Kicking candlestick pattern — a powerful 2-bar reversal: a strong
 * (near-marubozu) bar of one color, followed by a strong marubozu bar of
 * the opposite color that gaps cleanly past it, with no overlap at all.
 *
 * tol = tolerance * bar's own range (shadow allowance for "near-marubozu")
 *
 * bullish (+1.0): bar1 near-marubozu red (open near high, close near low),
 *                 bar2 near-marubozu green (open near low, close near
 *                 high) that gaps up entirely above bar1 (bar2.low > bar1.high).
 * bearish (-1.0): mirrored — bar1 near-marubozu green, bar2 near-marubozu
 *                 red gapping down entirely below bar1 (bar2.high < bar1.low).
 *
 * Output is 0.0 otherwise (including the first bar).
 */
class Kicking implements MuseIndicator<Bar, Float> {
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
		if (isRedMarubozu(bar1) && isGreenMarubozu(bar2) && bar2.low > bar1.high) return 1.0;
		if (isGreenMarubozu(bar1) && isRedMarubozu(bar2) && bar2.high < bar1.low) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return prev != null;
	public function name():String return "Kicking";

	public static function spec():IndicatorSpec {
		return {
			name: "kicking", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.05) : 0.05;
				return IndicatorCache.evalBar(h, "kicking:" + tol, Math.NaN,
					() -> new Kicking(tol), (i, b) -> (cast i : Kicking).update(b));
			}
		};
	}
}
