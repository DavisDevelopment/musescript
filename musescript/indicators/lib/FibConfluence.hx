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

typedef FibConfluenceOutput = {
	var price:Float; var strength:Float;
	var levels:LevelSet; var zones:ZoneSet; var pivots:PivotMarkSet; var labels:LabelSet;
}

class FibConfluence implements MuseIndicator<Bar, FibConfluenceOutput> {
	static inline var PIVOT_HISTORY = 6;
	static final RATIOS = [0.382, 0.5, 0.618];
	var swing:SwingGraph;
	var levelScratch:haxe.ds.Vector<Float>;
	var out:FibConfluenceOutput;

	public function new() {
		swing = new SwingGraph(0.05, PIVOT_HISTORY);
		levelScratch = new haxe.ds.Vector<Float>(PIVOT_HISTORY * RATIOS.length);
		out = {
			price: Math.NaN, strength: Math.NaN,
			levels: LevelSet.nan(), zones: ZoneSet.nan(),
			pivots: PivotMarkSet.nan(), labels: LabelSet.nan()
		};
	}

	public function update(bar:Bar):Null<FibConfluenceOutput> {
		swing.update(bar);
		var n = swing.pivotCount();
		if (n < 3) return null;
		var count = 0;
		for (i in 0...n - 1) {
			var start = swing.pivotAt(i).price;
			var end = swing.pivotAt(i + 1).price;
			for (ri in 0...RATIOS.length) levelScratch[count++] = RatioEngine.retrace(start, end, RATIOS[ri]);
		}
		var cl = RatioEngine.cluster(levelScratch, count, 0.03);
		if (cl == null) return null;
		out.price = cl.price; out.strength = cl.strength;
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		out.levels.clear();
		var take = count < LevelSet.CAP ? count : LevelSet.CAP;
		for (i in 0...take) out.levels.set(i, levelScratch[i], 0.5, st);
		out.levels.count = take * 1.0;
		out.zones.clear();
		var half = Math.abs(cl.price) * 0.015;
		out.zones.set(0, cl.price - half, cl.price + half, swing.currentBar() * 1.0, swing.currentBar() * 1.0,
			st, (ZoneKind.RetraceBand : Int) * 1.0);
		out.zones.count = 1;
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 6);
		out.labels.clear();
		out.labels.set(0, (GeomLabelCode.FibLevel : Int) * 1.0, cl.price, swing.currentBar() * 1.0, st);
		out.labels.count = 1;
		return out;
	}

	public function reset():Void { swing.reset(); out.levels.clear(); out.zones.clear(); out.pivots.clear(); out.labels.clear(); }
	public function warmupPeriod():Int return 3;
	public function isReady():Bool return swing.pivotCount() >= 3;
	public function name():String return "FIBCONF";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_confluence", args: [], ret: TObject([
				{name: "price", ty: TScalar}, {name: "strength", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "labels", ty: GeomVizSpec.labelObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:FibConfluenceOutput = {
					price: Math.NaN, strength: Math.NaN,
					levels: LevelSet.nan(), zones: ZoneSet.nan(),
					pivots: PivotMarkSet.nan(), labels: LabelSet.nan()
				};
				return IndicatorCache.evalBar(h, "fib_confluence", nanFill,
					() -> new FibConfluence(), (i, b) -> (cast i : FibConfluence).update(b));
			}
		};
	}
}
