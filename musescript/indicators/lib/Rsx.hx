package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * RSX — Jurik-style smoothed RSI — ported from wickra-core's `Rsx`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rsx.rs).
 *
 * The signed price change and its absolute value each run through three
 * cascaded "double-EMA with overshoot" stages (each stage is
 * x = 1.5*a - 0.5*b), then the two smoothed streams form the RSI-style ratio:
 *
 *   f18 = 3 / (length + 2),  f20 = 1 - f18
 *   each stage: a = f20*a + f18*in;  b = f18*a + f20*b;  out = 1.5*a - 0.5*b
 *   RSX = clamp((v14 / v1C + 1) * 50, 0, 100)     (50 when v1C == 0)
 *
 * Bounded in [0, 100]; a flat market returns the neutral 50. A non-finite
 * input leaves state untouched and returns the last value.
 */
class Rsx implements MuseIndicator<Float, Float> {
	public var length(default, null):Int;
	var f18:Float;
	var f20:Float;
	var prev:Null<Float>;
	var count:Int;
	// Signed-change cascade (three stages: a/b pairs).
	var sA0:Float;
	var sB0:Float;
	var sA1:Float;
	var sB1:Float;
	var sA2:Float;
	var sB2:Float;
	// Absolute-change cascade.
	var aA0:Float;
	var aB0:Float;
	var aA1:Float;
	var aB1:Float;
	var aA2:Float;
	var aB2:Float;
	var lastValue:Null<Float>;

	public function new(length:Int) {
		if (length <= 0) throw "Rsx: length must be > 0";
		this.length = length;
		f18 = 3.0 / (length + 2.0);
		f20 = 1.0 - f18;
		clearState();
	}

	/** Current value if available (null during warmup). */
	public function value():Null<Float> return lastValue;

	function clearState():Void {
		prev = null;
		count = 0;
		sA0 = 0.0; sB0 = 0.0; sA1 = 0.0; sB1 = 0.0; sA2 = 0.0; sB2 = 0.0;
		aA0 = 0.0; aB0 = 0.0; aA1 = 0.0; aB1 = 0.0; aA2 = 0.0; aB2 = 0.0;
		lastValue = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return lastValue;
		if (prev == null) {
			prev = price;
			return null;
		}
		var change = price - prev;
		prev = price;

		// Signed-change cascade. Each stage: a = f20*a + f18*in;
		// b = f18*a + f20*b; out = 1.5*a - 0.5*b.
		sA0 = f20 * sA0 + f18 * change;
		sB0 = f18 * sA0 + f20 * sB0;
		var v10In = 1.5 * sA0 - 0.5 * sB0;
		sA1 = f20 * sA1 + f18 * v10In;
		sB1 = f18 * sA1 + f20 * sB1;
		var v14In = 1.5 * sA1 - 0.5 * sB1;
		sA2 = f20 * sA2 + f18 * v14In;
		sB2 = f18 * sA2 + f20 * sB2;
		var v14 = 1.5 * sA2 - 0.5 * sB2;

		// Absolute-change cascade.
		var abs = Math.abs(change);
		aA0 = f20 * aA0 + f18 * abs;
		aB0 = f18 * aA0 + f20 * aB0;
		var v18In = 1.5 * aA0 - 0.5 * aB0;
		aA1 = f20 * aA1 + f18 * v18In;
		aB1 = f18 * aA1 + f20 * aB1;
		var v1cIn = 1.5 * aA1 - 0.5 * aB1;
		aA2 = f20 * aA2 + f18 * v1cIn;
		aB2 = f18 * aA2 + f20 * aB2;
		var v1c = 1.5 * aA2 - 0.5 * aB2;

		var v4 = v1c > 0.0 ? (v14 / v1c + 1.0) * 50.0 : 50.0;
		var rsx = v4 < 0.0 ? 0.0 : (v4 > 100.0 ? 100.0 : v4);

		count += 1;
		lastValue = rsx;
		return count >= length ? rsx : null;
	}

	public function reset():Void {
		clearState();
	}

	public function warmupPeriod():Int return length + 1;
	public function isReady():Bool return count >= length;
	public function name():String return "RSX";

	public static function spec():IndicatorSpec {
		return {
			name: "rsx", args: [TSeries, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "rsx:" + series + ":" + p, series, Math.NaN,
					() -> new Rsx(p), (i, v) -> (cast i : Rsx).update(v));
			}
		};
	}
}
