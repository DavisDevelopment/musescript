package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef FibTimeZonesOutput = {
	var onZone:Float; var barsToNext:Float;
	var zones:ZoneSet; var pivots:PivotMarkSet; var labels:LabelSet;
}

/**
 * Fibonacci Time Zones — demoted vs ssa_cycles; still emits TimeWindow zones for charts.
 */
class FibTimeZones implements MuseIndicator<Bar, FibTimeZonesOutput> {
	var swing:SwingGraph;
	var out:FibTimeZonesOutput;

	public function new() {
		swing = new SwingGraph(0.05, 2);
		out = {
			onZone: Math.NaN, barsToNext: Math.NaN,
			zones: ZoneSet.nan(), pivots: PivotMarkSet.nan(), labels: LabelSet.nan()
		};
	}

	public function update(bar:Bar):Null<FibTimeZonesOutput> {
		swing.update(bar);
		if (swing.pivotCount() == 0) return null;
		var anchor = swing.pivotAt(swing.pivotCount() - 1);
		var distance = swing.currentBar() - anchor.bar;
		// Scalar contract first (same loop as pre-viz FibTimeZones).
		var lo = 1; var hi = 2; var onZone = false;
		while (lo <= distance) {
			if (lo == distance) onZone = true;
			var next = lo + hi; lo = hi; hi = next;
		}
		out.onZone = onZone ? 1.0 : 0.0;
		out.barsToNext = lo - distance;
		var nextZoneBar = (anchor.bar + lo) * 1.0;
		// Chart TimeWindow markers — independent fib walk; does not touch barsToNext.
		var zLo = 1; var zHi = 2; var zoneIdx = 0;
		out.zones.clear();
		var st = GeomVizFill.statusOf(PivotStatus.Projected);
		var px = anchor.price;
		var band = Math.abs(px) * 0.002;
		if (!(band > 0)) band = 0.01;
		while (zLo <= distance + 20 && zoneIdx < ZoneSet.CAP) {
			var barAt = (anchor.bar + zLo) * 1.0;
			out.zones.set(zoneIdx, px - band, px + band, barAt, barAt, st, (ZoneKind.TimeWindow : Int) * 1.0);
			zoneIdx++;
			var zNext = zLo + zHi; zLo = zHi; zHi = zNext;
		}
		out.zones.count = zoneIdx * 1.0;
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 2);
		out.labels.clear();
		out.labels.set(0, (GeomLabelCode.Projected : Int) * 1.0, px, nextZoneBar, st);
		out.labels.count = 1;
		return out;
	}

	public function reset():Void { swing.reset(); out.zones.clear(); out.pivots.clear(); out.labels.clear(); }
	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.pivotCount() > 0;
	public function name():String return "FIBTIMEZ";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_time_zones", args: [], ret: TObject([
				{name: "onZone", ty: TScalar}, {name: "barsToNext", ty: TScalar},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "labels", ty: GeomVizSpec.labelObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:FibTimeZonesOutput = {
					onZone: Math.NaN, barsToNext: Math.NaN,
					zones: ZoneSet.nan(), pivots: PivotMarkSet.nan(), labels: LabelSet.nan()
				};
				return IndicatorCache.evalBar(h, "fib_time_zones", nanFill,
					() -> new FibTimeZones(), (i, b) -> (cast i : FibTimeZones).update(b));
			}
		};
	}
}
