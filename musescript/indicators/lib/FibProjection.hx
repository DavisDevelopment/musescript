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

typedef FibProjectionOutput = {
	var level618:Float; var level1000:Float; var level1618:Float; var level2618:Float;
	var levels:LevelSet; var pivots:PivotMarkSet; var forecast:ForecastBand; var zones:ZoneSet;
}

class FibProjection implements MuseIndicator<Bar, FibProjectionOutput> {
	var swing:SwingGraph;
	var out:FibProjectionOutput;

	public function new() {
		swing = new SwingGraph(0.05, 3);
		out = {
			level618: Math.NaN, level1000: Math.NaN, level1618: Math.NaN, level2618: Math.NaN,
			levels: LevelSet.nan(), pivots: PivotMarkSet.nan(),
			forecast: ForecastBand.nan(), zones: ZoneSet.nan()
		};
	}

	public function update(bar:Bar):Null<FibProjectionOutput> {
		swing.update(bar);
		if (swing.pivotCount() < 3) return null;
		var a = swing.pivotAt(0).price;
		var b = swing.pivotAt(1).price;
		var c = swing.pivotAt(2).price;
		out.level618 = RatioEngine.projectLeg(a, b, c, 0.618);
		out.level1000 = RatioEngine.projectLeg(a, b, c, 1.0);
		out.level1618 = RatioEngine.projectLeg(a, b, c, 1.618);
		out.level2618 = RatioEngine.projectLeg(a, b, c, 2.618);
		var st = GeomVizFill.statusOf(PivotStatus.Projected);
		out.levels.clear();
		out.levels.set(0, out.level618, 0.618, st);
		out.levels.set(1, out.level1000, 1.0, st);
		out.levels.set(2, out.level1618, 1.618, st);
		out.levels.set(3, out.level2618, 2.618, st);
		out.levels.count = 4;
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 3);
		var barNow = swing.currentBar() * 1.0;
		out.forecast.set(out.level618, out.level2618, barNow, barNow + 10);
		out.zones.clear();
		out.zones.set(0, out.level618, out.level1618, barNow, barNow + 8, st, (ZoneKind.Extension : Int) * 1.0);
		out.zones.count = 1;
		return out;
	}

	public function reset():Void { swing.reset(); out.levels.clear(); out.pivots.clear(); out.forecast.clear(); out.zones.clear(); }
	public function warmupPeriod():Int return 3;
	public function isReady():Bool return swing.pivotCount() >= 3;
	public function name():String return "FIBPROJ";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_projection", args: [], ret: TObject([
				{name: "level618", ty: TScalar}, {name: "level1000", ty: TScalar},
				{name: "level1618", ty: TScalar}, {name: "level2618", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "forecast", ty: GeomVizSpec.forecastObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:FibProjectionOutput = {
					level618: Math.NaN, level1000: Math.NaN, level1618: Math.NaN, level2618: Math.NaN,
					levels: LevelSet.nan(), pivots: PivotMarkSet.nan(),
					forecast: ForecastBand.nan(), zones: ZoneSet.nan()
				};
				return IndicatorCache.evalBar(h, "fib_projection", nanFill,
					() -> new FibProjection(), (i, b) -> (cast i : FibProjection).update(b));
			}
		};
	}
}
