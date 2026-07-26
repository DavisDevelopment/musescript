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

typedef GoldenPocketOutput = {
	var low:Float;
	var mid:Float;
	var high:Float;
	var levels:LevelSet;
	var zones:ZoneSet;
	var pivots:PivotMarkSet;
	var labels:LabelSet;
}

/** Golden Pocket — OTE band with viz zone + pivot anchors. */
class GoldenPocket implements MuseIndicator<Bar, GoldenPocketOutput> {
	var swing:SwingGraph;
	var out:GoldenPocketOutput;

	public function new(?threshold:Float) {
		swing = new SwingGraph(threshold != null ? threshold : 0.05, 2);
		out = {
			low: Math.NaN, mid: Math.NaN, high: Math.NaN,
			levels: LevelSet.nan(), zones: ZoneSet.nan(),
			pivots: PivotMarkSet.nan(), labels: LabelSet.nan()
		};
	}

	public function update(candle:Bar):Null<GoldenPocketOutput> {
		swing.update(candle);
		return zone();
	}

	function zone():Null<GoldenPocketOutput> {
		if (swing.pivotCount() < 2) return null;
		var start = swing.pivotAt(0).price;
		var end = swing.pivotAt(1).price;
		var edgeLow = RatioEngine.retrace(start, end, 0.618);
		var edgeHigh = RatioEngine.retrace(start, end, 0.65);
		var low = Math.min(edgeLow, edgeHigh);
		var high = Math.max(edgeLow, edgeHigh);
		out.low = low;
		out.mid = (low + high) / 2.0;
		out.high = high;

		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		out.levels.clear();
		out.levels.set(0, low, 0.618, st);
		out.levels.set(1, out.mid, 0.634, st);
		out.levels.set(2, high, 0.65, st);
		out.levels.count = 3;

		out.zones.clear();
		out.zones.set(0, low, high,
			swing.pivotAt(0).bar * 1.0, swing.currentBar() * 1.0,
			st, (ZoneKind.RetraceBand : Int) * 1.0);
		out.zones.count = 1;

		GeomVizFill.pivotsFromGraph(swing, out.pivots, 2);

		out.labels.clear();
		out.labels.set(0, (GeomLabelCode.FibLevel : Int) * 1.0, out.mid, swing.currentBar() * 1.0, st);
		out.labels.count = 1;
		return out;
	}

	public function reset():Void {
		swing.reset();
		out.levels.clear();
		out.zones.clear();
		out.pivots.clear();
		out.labels.clear();
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.pivotCount() >= 2;
	public function name():String return "GoldenPocket";

	public static function spec():IndicatorSpec {
		return {
			name: "golden_pocket", args: [], ret: TObject([
				{name: "low", ty: TScalar}, {name: "mid", ty: TScalar}, {name: "high", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "labels", ty: GeomVizSpec.labelObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:GoldenPocketOutput = {
					low: Math.NaN, mid: Math.NaN, high: Math.NaN,
					levels: LevelSet.nan(), zones: ZoneSet.nan(),
					pivots: PivotMarkSet.nan(), labels: LabelSet.nan()
				};
				return IndicatorCache.evalBar(h, "golden_pocket", nanFill,
					() -> new GoldenPocket(), (i, b) -> (cast i : GoldenPocket).update(b));
			}
		};
	}
}
