package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.GannAngles;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef GannAnglesIndOutput = {
	var ang1x1:Float;
	var ang1x2:Float;
	var ang2x1:Float;
	var ang1x4:Float;
	var ang4x1:Float;
	var levels:LevelSet;
	var rays:RaySet;
	var pivots:PivotMarkSet;
}

/** Streaming Gann fan — rays + level marks; requires explicit pricePerBar. */
class GannAnglesIndicator implements MuseIndicator<Bar, GannAnglesIndOutput> {
	var swing:SwingGraph;
	var pricePerBar:Float;
	var out:GannAnglesIndOutput;

	public function new(pricePerBar:Float, ?threshold:Float) {
		if (!(pricePerBar > 0) || !Math.isFinite(pricePerBar))
			throw "GannAnglesIndicator: pricePerBar must be finite and > 0";
		this.pricePerBar = pricePerBar;
		swing = new SwingGraph(threshold != null ? threshold : 0.05, 4);
		out = {
			ang1x1: Math.NaN, ang1x2: Math.NaN, ang2x1: Math.NaN,
			ang1x4: Math.NaN, ang4x1: Math.NaN,
			levels: LevelSet.nan(), rays: RaySet.nan(), pivots: PivotMarkSet.nan()
		};
	}

	public function update(bar:Bar):Null<GannAnglesIndOutput> {
		swing.update(bar);
		if (swing.pivotCount() < 1) return null;
		var origin = swing.pivotAt(swing.pivotCount() - 1);
		var bars = swing.currentBar() - origin.bar;
		if (bars < 0) bars = 0;
		var fan = GannAngles.fan(origin.price, bars, pricePerBar);
		out.ang1x1 = fan.ang1x1;
		out.ang1x2 = fan.ang1x2;
		out.ang2x1 = fan.ang2x1;
		out.ang1x4 = fan.ang1x4;
		out.ang4x1 = fan.ang4x1;

		var st = GeomVizFill.statusOf(PivotStatus.Projected);
		var stC = GeomVizFill.statusOf(PivotStatus.Confirmed);
		out.levels.clear();
		out.levels.set(0, fan.ang1x1, 1.0, st);
		out.levels.set(1, fan.ang1x2, 0.5, st);
		out.levels.set(2, fan.ang2x1, 2.0, st);
		out.levels.set(3, fan.ang1x4, 0.25, st);
		out.levels.set(4, fan.ang4x1, 4.0, st);
		out.levels.count = 5;

		out.rays.clear();
		var b0 = origin.bar * 1.0;
		var b1 = swing.currentBar() * 1.0;
		out.rays.set(0, origin.price, fan.ang1x1, b0, b1, st);
		out.rays.set(1, origin.price, fan.ang1x2, b0, b1, st);
		out.rays.set(2, origin.price, fan.ang2x1, b0, b1, st);
		out.rays.set(3, origin.price, fan.ang1x4, b0, b1, st);
		out.rays.set(4, origin.price, fan.ang4x1, b0, b1, st);
		out.rays.count = 5;

		GeomVizFill.pivotsFromGraph(swing, out.pivots, 2);
		return out;
	}

	public function reset():Void {
		swing.reset();
		out.levels.clear(); out.rays.clear(); out.pivots.clear();
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.pivotCount() >= 1;
	public function name():String return "GannAngles";

	public static function spec():IndicatorSpec {
		return {
			name: "gann_angles", args: [TScalar, TScalar], ret: TObject([
				{name: "ang1x1", ty: TScalar}, {name: "ang1x2", ty: TScalar}, {name: "ang2x1", ty: TScalar},
				{name: "ang1x4", ty: TScalar}, {name: "ang4x1", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "rays", ty: GeomVizSpec.rayObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()}
			]), minArgs: 1,
			eval: function(h, args) {
				var ppb = IndicatorCache.floatArg(args, 0, 1.0);
				var thr = IndicatorCache.floatArg(args, 1, 0.05);
				var nanFill:GannAnglesIndOutput = {
					ang1x1: Math.NaN, ang1x2: Math.NaN, ang2x1: Math.NaN,
					ang1x4: Math.NaN, ang4x1: Math.NaN,
					levels: LevelSet.nan(), rays: RaySet.nan(), pivots: PivotMarkSet.nan()
				};
				return IndicatorCache.evalBar(h, 'gann_angles:$ppb:$thr', nanFill,
					() -> new GannAnglesIndicator(ppb, thr), (i, b) -> (cast i : GannAnglesIndicator).update(b));
			}
		};
	}
}
