package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef FibChannelOutput = {
	var base:Float; var level618:Float; var level1000:Float; var level1618:Float;
	var levels:LevelSet; var rays:RaySet; var zones:ZoneSet; var pivots:PivotMarkSet;
}

class FibChannel implements MuseIndicator<Bar, FibChannelOutput> {
	var swing:SwingGraph;
	var out:FibChannelOutput;

	public function new() {
		swing = new SwingGraph(0.05, 3);
		out = {
			base: Math.NaN, level618: Math.NaN, level1000: Math.NaN, level1618: Math.NaN,
			levels: LevelSet.nan(), rays: RaySet.nan(), zones: ZoneSet.nan(), pivots: PivotMarkSet.nan()
		};
	}

	public function update(candle:Bar):Null<FibChannelOutput> {
		swing.update(candle);
		if (swing.pivotCount() < 3) return null;
		var p0 = swing.pivotAt(0); var p1 = swing.pivotAt(1); var p2 = swing.pivotAt(2);
		var slope = (p2.price - p0.price) / (p2.bar - p0.bar);
		inline function baseAt(bar:Int):Float return p0.price + slope * (bar - p0.bar);
		var width = p1.price - baseAt(p1.bar);
		var base = baseAt(swing.currentBar());
		out.base = base;
		out.level618 = base + 0.618 * width;
		out.level1000 = base + 1.0 * width;
		out.level1618 = base + 1.618 * width;
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		out.levels.clear();
		out.levels.set(0, out.base, 0.0, st);
		out.levels.set(1, out.level618, 0.618, st);
		out.levels.set(2, out.level1000, 1.0, st);
		out.levels.set(3, out.level1618, 1.618, st);
		out.levels.count = 4;
		out.rays.clear();
		var b0 = p0.bar * 1.0; var b1 = swing.currentBar() * 1.0;
		out.rays.set(0, p0.price, base, b0, b1, st);
		out.rays.set(1, p0.price + 0.618 * width, out.level618, b0, b1, st);
		out.rays.count = 2;
		out.zones.clear();
		out.zones.set(0, Math.min(base, out.level1000), Math.max(base, out.level1000), b0, b1, st, (ZoneKind.Channel : Int) * 1.0);
		out.zones.count = 1;
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 3);
		return out;
	}

	public function reset():Void { swing.reset(); out.levels.clear(); out.rays.clear(); out.zones.clear(); out.pivots.clear(); }
	public function warmupPeriod():Int return 3;
	public function isReady():Bool return swing.pivotCount() >= 3;
	public function name():String return "FibChannel";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_channel", args: [], ret: TObject([
				{name: "base", ty: TScalar}, {name: "level618", ty: TScalar},
				{name: "level1000", ty: TScalar}, {name: "level1618", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "rays", ty: GeomVizSpec.rayObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:FibChannelOutput = {
					base: Math.NaN, level618: Math.NaN, level1000: Math.NaN, level1618: Math.NaN,
					levels: LevelSet.nan(), rays: RaySet.nan(), zones: ZoneSet.nan(), pivots: PivotMarkSet.nan()
				};
				return IndicatorCache.evalBar(h, "fib_channel", nanFill,
					() -> new FibChannel(), (i, b) -> (cast i : FibChannel).update(b));
			}
		};
	}
}
