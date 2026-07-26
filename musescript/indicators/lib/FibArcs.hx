package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef FibArcsOutput = {
	var arc382:Float; var arc500:Float; var arc618:Float;
	var levels:LevelSet; var zones:ZoneSet; var pivots:PivotMarkSet; var arcs:ArcSet;
}

class FibArcs implements MuseIndicator<Bar, FibArcsOutput> {
	var swing:SwingGraph;
	var out:FibArcsOutput;
	static var RATIOS:Array<Float> = [0.382, 0.5, 0.618];

	public function new() {
		swing = new SwingGraph(0.05, 2);
		out = {
			arc382: Math.NaN, arc500: Math.NaN, arc618: Math.NaN,
			levels: LevelSet.nan(), zones: ZoneSet.nan(), pivots: PivotMarkSet.nan(), arcs: ArcSet.nan()
		};
	}

	public function update(candle:Bar):Null<FibArcsOutput> {
		swing.update(candle);
		if (swing.pivotCount() < 2) return null;
		var start = swing.pivotAt(0); var end = swing.pivotAt(1);
		var spanBars = (end.bar - start.bar) * 1.0;
		if (spanBars <= 0) return null;
		var priceSpan = Math.abs(start.price - end.price);
		var u = (swing.currentBar() - end.bar) * 1.0 / spanBars;
		var curve = Math.sqrt(Math.max(0.0, 1.0 - u * u));
		inline function arc(r:Float):Float return end.price + (start.price - end.price) * r * curve;
		out.arc382 = arc(0.382); out.arc500 = arc(0.5); out.arc618 = arc(0.618);
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		var formSt = GeomVizFill.statusOf(PivotStatus.Forming);
		out.levels.clear();
		out.levels.set(0, out.arc382, 0.382, st);
		out.levels.set(1, out.arc500, 0.5, st);
		out.levels.set(2, out.arc618, 0.618, st);
		out.levels.count = 3;
		out.zones.clear();
		out.zones.set(0, Math.min(out.arc382, out.arc618), Math.max(out.arc382, out.arc618),
			end.bar * 1.0, swing.currentBar() * 1.0, st, (ZoneKind.RetraceBand : Int) * 1.0);
		out.zones.count = 1;
		out.arcs.clear();
		for (i in 0...RATIOS.length) {
			var r = RATIOS[i];
			var rBars = Math.max(6.0, spanBars * r * 1.4);
			out.arcs.set(i, start.bar * 1.0, start.price, rBars, priceSpan * r, formSt, r);
		}
		out.arcs.count = RATIOS.length * 1.0;
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 2);
		return out;
	}

	public function reset():Void {
		swing.reset();
		out.levels.clear(); out.zones.clear(); out.pivots.clear(); out.arcs.clear();
	}
	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.pivotCount() >= 2;
	public function name():String return "FibArcs";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_arcs", args: [], ret: TObject([
				{name: "arc382", ty: TScalar}, {name: "arc500", ty: TScalar}, {name: "arc618", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "arcs", ty: GeomVizSpec.arcObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:FibArcsOutput = {
					arc382: Math.NaN, arc500: Math.NaN, arc618: Math.NaN,
					levels: LevelSet.nan(), zones: ZoneSet.nan(), pivots: PivotMarkSet.nan(), arcs: ArcSet.nan()
				};
				return IndicatorCache.evalBar(h, "fib_arcs", nanFill,
					() -> new FibArcs(), (i, b) -> (cast i : FibArcs).update(b));
			}
		};
	}
}
