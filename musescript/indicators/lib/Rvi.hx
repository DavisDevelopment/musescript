package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Relative Vigor Index — ported from wickra-core's `Rvi`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/rvi.rs).
 *
 *   RVI = SMA(close - open, period) / SMA(high - low, period)
 *
 * Donald Dorsey's ratio of intra-bar drive to intra-bar range. The
 * denominator's rolling sum can fall to zero on a perfectly flat stretch,
 * in which case the indicator holds its previous value.
 */
class Rvi implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var nums:RingBuffer<Float>;
	var dens:RingBuffer<Float>;
	var sumNum:Float;
	var sumDen:Float;
	var current:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Rvi: period must be > 0";
		this.period = period;
		reset();
	}

	/** Current value if available (null during warmup). */
	public function value():Null<Float> return current;

	public function update(bar:Bar):Null<Float> {
		var num = bar.close - bar.open;
		var den = bar.high - bar.low;
		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = nums.isFull();
		var oldNum = nums.push(num);
		var oldDen = dens.push(den);
		if (wasFull) {
			sumNum -= oldNum;
			sumDen -= oldDen;
		}
		sumNum += num;
		sumDen += den;
		if (nums.length < period) return null;
		if (sumDen <= 0.0) {
			// Window of perfectly flat (zero-range) bars: ratio undefined.
			// Hold the previous value rather than emitting NaN / inf.
			return current;
		}
		var value = sumNum / sumDen;
		current = value;
		return value;
	}

	public function reset():Void {
		nums = new RingBuffer(period);
		dens = new RingBuffer(period);
		sumNum = 0.0;
		sumDen = 0.0;
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return current != null;
	public function name():String return "RVI";

	public static function spec():IndicatorSpec {
		return {
			name: "rvi", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 10);
				return IndicatorCache.evalBar(h, "rvi:" + p, Math.NaN,
					() -> new Rvi(p), (i, b) -> (cast i : Rvi).update(b));
			}
		};
	}
}
