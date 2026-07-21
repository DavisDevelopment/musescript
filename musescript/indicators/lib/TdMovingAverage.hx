package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/** Output of `TdMovingAverage`: the fast (st1) and slow (st2) moving-average lines. */
typedef TdMovingAverageOutput = {
	var st1:Float;
	var st2:Float;
}

/**
 * Tom DeMark TD Moving Averages — ported from wickra-core's `TdMovingAverage`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_moving_average.rs).
 *
 * A two-line trend ribbon computed on the median price (high + low) / 2:
 *   st1 = SMA(median, periodSt1)   (fast / "Sequential Trend 1")
 *   st2 = SMA(median, periodSt2)   (slow / "Sequential Trend 2")
 * `periodSt1` must be strictly smaller than `periodSt2`; the first value
 * lands once the slow average is seeded.
 */
class TdMovingAverage implements MuseIndicator<Bar, TdMovingAverageOutput> {
	var st1:Sma;
	var st2:Sma;
	var periodSt1:Int;
	var periodSt2:Int;
	var last:Null<TdMovingAverageOutput>;

	public function new(periodSt1:Int, periodSt2:Int) {
		if (periodSt1 <= 0 || periodSt2 <= 0) throw "TdMovingAverage: periods must be > 0";
		if (periodSt1 >= periodSt2) throw "TD moving average ST1 period must be strictly less than ST2";
		st1 = new Sma(periodSt1);
		st2 = new Sma(periodSt2);
		this.periodSt1 = periodSt1;
		this.periodSt2 = periodSt2;
		last = null;
	}

	/** Configured (periodSt1, periodSt2). */
	public function periods():{st1:Int, st2:Int} return {st1: periodSt1, st2: periodSt2};

	/** Current value if available. */
	public function value():Null<TdMovingAverageOutput> return last;

	public function update(bar:Bar):Null<TdMovingAverageOutput> {
		var price = (bar.high + bar.low) / 2;
		var fast = st1.update(price);
		var slow = st2.update(price);
		if (fast != null && slow != null) {
			var out = {st1: (fast : Float), st2: (slow : Float)};
			last = out;
			return out;
		}
		return null;
	}

	public function reset():Void {
		st1.reset();
		st2.reset();
		last = null;
	}

	public function warmupPeriod():Int return periodSt2;
	public function isReady():Bool return last != null;
	public function name():String return "TDMovingAverage";

	public static function spec():IndicatorSpec {
		return {
			name: "td_moving_average", args: [TWindow, TWindow], ret: TObject([
				{name: "st1", ty: TScalar}, {name: "st2", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var p1 = IndicatorCache.intArg(args, 0, 5);
				var p2 = IndicatorCache.intArg(args, 1, 13);
				return IndicatorCache.evalBar(h, "td_moving_average:" + p1 + ":" + p2,
					{st1: Math.NaN, st2: Math.NaN},
					() -> new TdMovingAverage(p1, p2), (i, b) -> (cast i : TdMovingAverage).update(b));
			}
		};
	}
}
