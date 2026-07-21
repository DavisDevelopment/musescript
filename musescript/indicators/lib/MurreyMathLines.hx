package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Murrey Math Lines output: the nine levels from 0/8 (support) to 8/8 (resistance). */
typedef MurreyMathLinesOutput = {
	var mm8_8:Float;
	var mm7_8:Float;
	var mm6_8:Float;
	var mm5_8:Float;
	var mm4_8:Float;
	var mm3_8:Float;
	var mm2_8:Float;
	var mm1_8:Float;
	var mm0_8:Float;
}

/**
 * Murrey Math Lines — ported from wickra-core's `MurreyMathLines`
 * (vendor/wickra/crates/wickra-core/src/indicators/murrey_math_lines.rs).
 *
 * T. H. Murrey's grid that divides the recent trading range into eighths,
 * each acting as support/resistance:
 *
 *   HH = highest high over `period`,  LL = lowest low over `period`
 *   step = (HH − LL) / 8
 *   mm{i}_8 = LL + i · step       for i = 0..8
 *
 * First value after `period` inputs; a degenerate flat frame (HH == LL)
 * collapses every line onto the price.
 */
class MurreyMathLines implements MuseIndicator<Bar, MurreyMathLinesOutput> {
	var period:Int;
	var highs:Array<Float>;
	var lows:Array<Float>;
	var last:Null<MurreyMathLinesOutput>;

	public function new(period:Int) {
		if (period <= 0) throw "MurreyMathLines: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(candle:Bar):Null<MurreyMathLinesOutput> {
		if (highs.length == period) {
			highs.shift();
			lows.shift();
		}
		highs.push(candle.high);
		lows.push(candle.low);
		if (highs.length < period) return null;
		var hh = Math.NEGATIVE_INFINITY;
		for (h in highs) if (h > hh) hh = h;
		var ll = Math.POSITIVE_INFINITY;
		for (l in lows) if (l < ll) ll = l;
		var step = (hh - ll) / 8.0;
		var out:MurreyMathLinesOutput = {
			mm0_8: ll,
			mm1_8: ll + 1.0 * step,
			mm2_8: ll + 2.0 * step,
			mm3_8: ll + 3.0 * step,
			mm4_8: ll + 4.0 * step,
			mm5_8: ll + 5.0 * step,
			mm6_8: ll + 6.0 * step,
			mm7_8: ll + 7.0 * step,
			mm8_8: ll + 8.0 * step
		};
		last = out;
		return out;
	}

	public function reset():Void {
		highs = [];
		lows = [];
		last = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "MurreyMathLines";

	public static function spec():IndicatorSpec {
		return {
			name: "murrey_math_lines", args: [TWindow], ret: TObject([
				{name: "mm8_8", ty: TScalar}, {name: "mm7_8", ty: TScalar}, {name: "mm6_8", ty: TScalar},
				{name: "mm5_8", ty: TScalar}, {name: "mm4_8", ty: TScalar}, {name: "mm3_8", ty: TScalar},
				{name: "mm2_8", ty: TScalar}, {name: "mm1_8", ty: TScalar}, {name: "mm0_8", ty: TScalar}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 64);
				var nanFill = {
					mm8_8: Math.NaN, mm7_8: Math.NaN, mm6_8: Math.NaN, mm5_8: Math.NaN, mm4_8: Math.NaN,
					mm3_8: Math.NaN, mm2_8: Math.NaN, mm1_8: Math.NaN, mm0_8: Math.NaN
				};
				return IndicatorCache.evalBar(h, "murrey_math_lines:" + p, nanFill,
					() -> new MurreyMathLines(p), (i, b) -> (cast i : MurreyMathLines).update(b));
			}
		};
	}
}
