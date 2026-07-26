package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef MurreyMathLinesOutput = {
	var mm8_8:Float; var mm7_8:Float; var mm6_8:Float; var mm5_8:Float; var mm4_8:Float;
	var mm3_8:Float; var mm2_8:Float; var mm1_8:Float; var mm0_8:Float;
	var levels:LevelSet; var zones:ZoneSet; var pivots:PivotMarkSet;
}

class MurreyMathLines implements MuseIndicator<Bar, MurreyMathLinesOutput> {
	var period:Int;
	var highs:RingBuffer<Float>;
	var lows:RingBuffer<Float>;
	var last:Null<MurreyMathLinesOutput>;
	var out:MurreyMathLinesOutput;

	public function new(period:Int) {
		if (period <= 0) throw "MurreyMathLines: period must be > 0";
		this.period = period;
		out = {
			mm0_8: Math.NaN, mm1_8: Math.NaN, mm2_8: Math.NaN, mm3_8: Math.NaN, mm4_8: Math.NaN,
			mm5_8: Math.NaN, mm6_8: Math.NaN, mm7_8: Math.NaN, mm8_8: Math.NaN,
			levels: LevelSet.nan(), zones: ZoneSet.nan(), pivots: PivotMarkSet.nan()
		};
		reset();
	}

	public function update(candle:Bar):Null<MurreyMathLinesOutput> {
		highs.push(candle.high);
		lows.push(candle.low);
		if (highs.length < period) return null;
		var hh = Math.NEGATIVE_INFINITY;
		var ll = Math.POSITIVE_INFINITY;
		for (i in 0...highs.length) {
			var h = highs.at(i); var l = lows.at(i);
			if (h > hh) hh = h;
			if (l < ll) ll = l;
		}
		var step = (hh - ll) / 8.0;
		out.mm0_8 = ll;
		out.mm1_8 = ll + 1.0 * step;
		out.mm2_8 = ll + 2.0 * step;
		out.mm3_8 = ll + 3.0 * step;
		out.mm4_8 = ll + 4.0 * step;
		out.mm5_8 = ll + 5.0 * step;
		out.mm6_8 = ll + 6.0 * step;
		out.mm7_8 = ll + 7.0 * step;
		out.mm8_8 = ll + 8.0 * step;
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		out.levels.clear();
		for (i in 0...8) out.levels.set(i, ll + i * step, i / 8.0, st);
		// CAP=8 so mm8 sits in zone only
		out.levels.count = 8;
		out.zones.clear();
		out.zones.set(0, ll, hh, candle.index * 1.0, candle.index * 1.0, st, (ZoneKind.MurreyOctave : Int) * 1.0);
		out.zones.count = 1;
		out.pivots.clear();
		out.pivots.set(0, ll, -1, candle.index * 1.0, st);
		out.pivots.set(1, hh, 1, candle.index * 1.0, st);
		out.pivots.count = 2;
		last = out;
		return out;
	}

	public function reset():Void {
		highs = new RingBuffer(period);
		lows = new RingBuffer(period);
		last = null;
		out.levels.clear(); out.zones.clear(); out.pivots.clear();
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return last != null;
	public function name():String return "MurreyMathLines";

	public static function spec():IndicatorSpec {
		return {
			name: "murrey_math_lines", args: [TWindow], ret: TObject([
				{name: "mm8_8", ty: TScalar}, {name: "mm7_8", ty: TScalar}, {name: "mm6_8", ty: TScalar},
				{name: "mm5_8", ty: TScalar}, {name: "mm4_8", ty: TScalar}, {name: "mm3_8", ty: TScalar},
				{name: "mm2_8", ty: TScalar}, {name: "mm1_8", ty: TScalar}, {name: "mm0_8", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()}
			]), minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 64);
				var nanFill:MurreyMathLinesOutput = {
					mm8_8: Math.NaN, mm7_8: Math.NaN, mm6_8: Math.NaN, mm5_8: Math.NaN, mm4_8: Math.NaN,
					mm3_8: Math.NaN, mm2_8: Math.NaN, mm1_8: Math.NaN, mm0_8: Math.NaN,
					levels: LevelSet.nan(), zones: ZoneSet.nan(), pivots: PivotMarkSet.nan()
				};
				return IndicatorCache.evalBar(h, "murrey_math_lines:" + p, nanFill,
					() -> new MurreyMathLines(p), (i, b) -> (cast i : MurreyMathLines).update(b));
			}
		};
	}
}
