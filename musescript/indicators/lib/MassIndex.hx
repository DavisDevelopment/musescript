package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Mass Index (Donald Dorsey): sums the ratio of a single- to double-smoothed
 * high-low range over a trailing window, flagging range expansion
 * ("reversal bulge") independent of price direction.
 *
 * ema1 = EMA(high - low, emaPeriod)
 * ema2 = EMA(ema1, emaPeriod)
 * ratio = ema1 / ema2
 * MassIndex = sum(ratio, period)
 */
class MassIndex implements MuseIndicator<Bar, Float> {
	var ema1:Ema;
	var ema2:Ema;
	var period:Int;
	var ratioWindow:Array<Float>;
	var sum:Float;

	public function new(emaPeriod:Int, period:Int) {
		if (period <= 0) throw "MassIndex: period must be > 0";
		ema1 = new Ema(emaPeriod);
		ema2 = new Ema(emaPeriod);
		this.period = period;
		ratioWindow = [];
		sum = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var r1 = ema1.update(bar.high - bar.low);
		if (r1 == null) return null;
		var r2 = ema2.update(r1);
		if (r2 == null) return null;
		var ratio = r2 == 0.0 ? 0.0 : r1 / r2;

		if (ratioWindow.length == period) sum -= ratioWindow.shift();
		ratioWindow.push(ratio);
		sum += ratio;

		if (ratioWindow.length < period) return null;
		return sum;
	}

	public function reset():Void {
		ema1.reset();
		ema2.reset();
		ratioWindow = [];
		sum = 0.0;
	}

	public function warmupPeriod():Int return ema1.period * 2 + period;
	public function isReady():Bool return ratioWindow.length == period;
	public function name():String return "MassIndex";

	public static function spec():IndicatorSpec {
		return {
			name: "mass_index", args: [TWindow, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var emaPeriod = args.length > 0 ? IndicatorCache.intArg(args, 0, 9) : 9;
				var period = IndicatorCache.intArg(args, 1, 25);
				return IndicatorCache.evalBar(h, "mass_index:" + emaPeriod + ":" + period, Math.NaN,
					() -> new MassIndex(emaPeriod, period), (i, b) -> (cast i : MassIndex).update(b));
			}
		};
	}
}
