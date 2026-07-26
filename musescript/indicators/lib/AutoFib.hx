package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.RatioEngine;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef AutoFibOutput = {
	var level0:Float; var level236:Float; var level382:Float; var level500:Float;
	var level618:Float; var level786:Float; var level1000:Float;
	var levels:LevelSet; var pivots:PivotMarkSet; var zones:ZoneSet;
}

class AutoFib implements MuseIndicator<Bar, AutoFibOutput> {
	static final RATIOS = [0.0, 0.236, 0.382, 0.5, 0.618, 0.786, 1.0];
	var swing:SwingGraph;
	var out:AutoFibOutput;
	var priceScratch:haxe.ds.Vector<Float>;
	var ratioScratch:haxe.ds.Vector<Float>;

	public function new() {
		swing = new SwingGraph(0.05, 6);
		priceScratch = new haxe.ds.Vector<Float>(8);
		ratioScratch = new haxe.ds.Vector<Float>(8);
		out = {
			level0: Math.NaN, level236: Math.NaN, level382: Math.NaN, level500: Math.NaN,
			level618: Math.NaN, level786: Math.NaN, level1000: Math.NaN,
			levels: LevelSet.nan(), pivots: PivotMarkSet.nan(), zones: ZoneSet.nan()
		};
	}

	public function update(candle:Bar):Null<AutoFibOutput> {
		swing.update(candle);
		var n = swing.pivotCount();
		if (n < 2) return null;
		var bestIdx = 0; var bestMag = -1.0;
		for (i in 0...n - 1) {
			var mag = Math.abs(swing.pivotAt(i).price - swing.pivotAt(i + 1).price);
			if (mag >= bestMag) { bestMag = mag; bestIdx = i; }
		}
		var start = swing.pivotAt(bestIdx).price;
		var end = swing.pivotAt(bestIdx + 1).price;
		out.level0 = RatioEngine.retrace(start, end, 0.0);
		out.level236 = RatioEngine.retrace(start, end, 0.236);
		out.level382 = RatioEngine.retrace(start, end, 0.382);
		out.level500 = RatioEngine.retrace(start, end, 0.5);
		out.level618 = RatioEngine.retrace(start, end, 0.618);
		out.level786 = RatioEngine.retrace(start, end, 0.786);
		out.level1000 = RatioEngine.retrace(start, end, 1.0);
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		for (i in 0...RATIOS.length) {
			priceScratch[i] = RatioEngine.retrace(start, end, RATIOS[i]);
			ratioScratch[i] = RATIOS[i];
		}
		GeomVizFill.levels(priceScratch, ratioScratch, RATIOS.length, st, out.levels);
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 6);
		out.zones.clear();
		out.zones.set(0, Math.min(out.level618, out.level786), Math.max(out.level618, out.level786),
			swing.pivotAt(bestIdx).bar * 1.0, swing.currentBar() * 1.0, st, (ZoneKind.RetraceBand : Int) * 1.0);
		out.zones.count = 1;
		return out;
	}

	public function reset():Void { swing.reset(); out.levels.clear(); out.pivots.clear(); out.zones.clear(); }
	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.pivotCount() >= 2;
	public function name():String return "AutoFib";

	public static function spec():IndicatorSpec {
		return {
			name: "auto_fib", args: [], ret: TObject([
				{name: "level0", ty: TScalar}, {name: "level236", ty: TScalar}, {name: "level382", ty: TScalar},
				{name: "level500", ty: TScalar}, {name: "level618", ty: TScalar}, {name: "level786", ty: TScalar},
				{name: "level1000", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:AutoFibOutput = {
					level0: Math.NaN, level236: Math.NaN, level382: Math.NaN, level500: Math.NaN,
					level618: Math.NaN, level786: Math.NaN, level1000: Math.NaN,
					levels: LevelSet.nan(), pivots: PivotMarkSet.nan(), zones: ZoneSet.nan()
				};
				return IndicatorCache.evalBar(h, "auto_fib", nanFill,
					() -> new AutoFib(), (i, b) -> (cast i : AutoFib).update(b));
			}
		};
	}
}
