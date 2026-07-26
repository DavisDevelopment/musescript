package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef FibFanOutput = {
	var fan382:Float; var fan500:Float; var fan618:Float;
	var levels:LevelSet; var rays:RaySet; var pivots:PivotMarkSet;
}

class FibFan implements MuseIndicator<Bar, FibFanOutput> {
	var swing:SwingGraph;
	var out:FibFanOutput;

	public function new() {
		swing = new SwingGraph(0.05, 2);
		out = {
			fan382: Math.NaN, fan500: Math.NaN, fan618: Math.NaN,
			levels: LevelSet.nan(), rays: RaySet.nan(), pivots: PivotMarkSet.nan()
		};
	}

	public function update(bar:Bar):Null<FibFanOutput> {
		swing.update(bar);
		if (swing.pivotCount() < 2) return null;
		var start = swing.pivotAt(0);
		var end = swing.pivotAt(1);
		var spanBars = end.bar - start.bar;
		if (spanBars <= 0) return null;
		var elapsed = swing.currentBar() - start.bar;
		var progress = elapsed / spanBars;
		inline function line(r:Float):Float return start.price + r * (end.price - start.price) * progress;
		out.fan382 = line(0.382);
		out.fan500 = line(0.5);
		out.fan618 = line(0.618);
		var st = GeomVizFill.statusOf(PivotStatus.Confirmed);
		out.levels.clear();
		out.levels.set(0, out.fan382, 0.382, st);
		out.levels.set(1, out.fan500, 0.5, st);
		out.levels.set(2, out.fan618, 0.618, st);
		out.levels.count = 3;
		out.rays.clear();
		var b0 = start.bar * 1.0; var b1 = swing.currentBar() * 1.0;
		out.rays.set(0, start.price, out.fan382, b0, b1, st);
		out.rays.set(1, start.price, out.fan500, b0, b1, st);
		out.rays.set(2, start.price, out.fan618, b0, b1, st);
		out.rays.count = 3;
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 2);
		return out;
	}

	public function reset():Void { swing.reset(); out.levels.clear(); out.rays.clear(); out.pivots.clear(); }
	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.pivotCount() >= 2;
	public function name():String return "FIBFAN";

	public static function spec():IndicatorSpec {
		return {
			name: "fib_fan", args: [], ret: TObject([
				{name: "fan382", ty: TScalar}, {name: "fan500", ty: TScalar}, {name: "fan618", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "rays", ty: GeomVizSpec.rayObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill:FibFanOutput = {
					fan382: Math.NaN, fan500: Math.NaN, fan618: Math.NaN,
					levels: LevelSet.nan(), rays: RaySet.nan(), pivots: PivotMarkSet.nan()
				};
				return IndicatorCache.evalBar(h, "fib_fan", nanFill,
					() -> new FibFan(), (i, b) -> (cast i : FibFan).update(b));
			}
		};
	}
}
