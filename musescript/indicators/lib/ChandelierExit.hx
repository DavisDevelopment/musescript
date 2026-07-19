package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Atr;
import musescript.types.MuseType;

/** Chandelier Exit output: the long (trailing-long) and short (trailing-short) stop levels. */
typedef ChandelierExitOutput = {
	var longStop:Float;
	var shortStop:Float;
}

/**
 * Chandelier Exit: ATR-based trailing stop anchored to the highest high /
 * lowest low of the trailing `period` bars.
 *
 * long  = highestHigh(period) - multiplier * ATR(period)
 * short = lowestLow(period) + multiplier * ATR(period)
 */
class ChandelierExit implements MuseIndicator<Bar, ChandelierExitOutput> {
	var period:Int;
	var multiplier:Float;
	var atr:Atr;
	var highs:Array<Float>;
	var lows:Array<Float>;

	public function new(period:Int, multiplier:Float) {
		if (!Math.isFinite(multiplier) || multiplier <= 0.0) throw "ChandelierExit: multiplier must be positive and finite";
		this.period = period;
		this.multiplier = multiplier;
		atr = new Atr(period);
		highs = [];
		lows = [];
	}

	public function update(bar:Bar):Null<ChandelierExitOutput> {
		var atrVal = atr.update(bar);

		if (highs.length == period) highs.shift();
		highs.push(bar.high);
		if (lows.length == period) lows.shift();
		lows.push(bar.low);

		if (atrVal == null) return null;

		var hh = highs[0];
		for (v in highs) if (v > hh) hh = v;
		var ll = lows[0];
		for (v in lows) if (v < ll) ll = v;

		return { longStop: hh - multiplier * atrVal, shortStop: ll + multiplier * atrVal };
	}

	public function reset():Void {
		atr.reset();
		highs = [];
		lows = [];
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return atr.isReady();
	public function name():String return "ChandelierExit";

	public static function spec():IndicatorSpec {
		return {
			name: "chandelier_exit", args: [TWindow, TScalar], ret: TObject([
				{name: "longStop", ty: TScalar}, {name: "shortStop", ty: TScalar}
			]), minArgs: 2,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 22);
				var m = IndicatorCache.floatArg(args, 1, 3.0);
				var key = "chandelier_exit:" + p + ":" + m;
				return IndicatorCache.evalBar(h, key, { longStop: Math.NaN, shortStop: Math.NaN },
					() -> new ChandelierExit(p, m), (i, b) -> (cast i : ChandelierExit).update(b));
			}
		};
	}
}
