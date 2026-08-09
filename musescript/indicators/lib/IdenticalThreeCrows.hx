package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Identical Three Crows candlestick pattern — a strong 3-bar bearish
 * continuation: three consecutive long red bars, each opening at (or very
 * near) the previous bar's close and closing near its own low, each
 * progressively lower.
 *
 * tol = tolerance * body of the bar being checked
 *
 * pattern (-1.0) when, for each pair of consecutive bars in the 3-bar
 * window: both red with a real body, the later bar opens within `tol` of
 * the earlier bar's close, closes near its own low (within `tol` of low),
 * and closes below the earlier bar's close.
 *
 * Output is 0.0 otherwise.
 */
class IdenticalThreeCrows implements MuseIndicator<Bar, Float> {
	var tolerance:Float;
	var buf:RingBuffer<Bar>;

	public function new(tolerance:Float = 0.1) {
		this.tolerance = Math.max(0.0, Math.min(tolerance, 0.9999));
		reset();
	}

	public function update(bar:Bar):Null<Float> {
		buf.push(bar);
		if (buf.length < 3) return 0.0;
		return compute(buf);
	}

	function compute(w:RingBuffer<Bar>):Float {
		for (i in 0...3) if (w.oldest(i).close >= w.oldest(i).open) return 0.0; // all three must be red

		for (i in 1...3) {
			var a = w.oldest(i - 1);
			var b = w.oldest(i);
			var bodyB = b.open - b.close;
			if (bodyB <= 0.0) return 0.0;
			var tol = tolerance * bodyB;
			if (Math.abs(b.open - a.close) > tol) return 0.0; // opens near prior close
			if ((b.close - b.low) > tol) return 0.0; // closes near its own low
			if (b.close >= a.close) return 0.0; // progressively lower
		}
		return -1.0;
	}

	public function reset():Void {
		buf = new RingBuffer(3);
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return buf.length == 3;
	public function name():String return "IdenticalThreeCrows";

	public static function spec():IndicatorSpec {
		return {
			name: "identical_three_crows", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.1) : 0.1;
				return IndicatorCache.evalBar(h, "identical_three_crows:" + tol, Math.NaN,
					() -> new IdenticalThreeCrows(tol), (i, b) -> (cast i : IdenticalThreeCrows).update(b));
			}
		};
	}
}
