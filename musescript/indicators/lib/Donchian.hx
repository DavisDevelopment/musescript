package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Donchian Channel output: upper/middle/lower bands. */
typedef DonchianOutput = {
	var upper:Float;
	var middle:Float;
	var lower:Float;
}

/**
 * Donchian Channel: the highest high / lowest low over the trailing
 * `period` bars (current bar included), with the midline their average.
 *
 * upper  = highestHigh(period)
 * lower  = lowestLow(period)
 * middle = (upper + lower) / 2
 */
class Donchian implements MuseIndicator<Bar, DonchianOutput> {
	var period:Int;
	var highs:Array<Float>;
	var lows:Array<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Donchian: period must be > 0";
		this.period = period;
		highs = [];
		lows = [];
	}

	public function update(bar:Bar):Null<DonchianOutput> {
		if (highs.length == period) highs.shift();
		highs.push(bar.high);
		if (lows.length == period) lows.shift();
		lows.push(bar.low);
		if (highs.length < period) return null;

		var hh = highs[0];
		for (v in highs) if (v > hh) hh = v;
		var ll = lows[0];
		for (v in lows) if (v < ll) ll = v;
		return { upper: hh, middle: (hh + ll) / 2.0, lower: ll };
	}

	public function reset():Void {
		highs = [];
		lows = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return highs.length == period;
	public function name():String return "Donchian";

	public static function spec():IndicatorSpec {
		return {
			name: "donchian", args: [TWindow], ret: TObject([
				{name: "upper", ty: TScalar}, {name: "middle", ty: TScalar}, {name: "lower", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "donchian:" + p, { upper: Math.NaN, middle: Math.NaN, lower: Math.NaN },
					() -> new Donchian(p), (i, b) -> (cast i : Donchian).update(b));
			}
		};
	}
}
