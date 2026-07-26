package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SquareOfNine;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

/**
 * Square of Nine — math spiral levels from last Confirmed swing (GEOM_GANN family).
 * Emits `levels` + `pivots` + capped `rings` for live chart paint.
 */
typedef SquareOfNineOutput = {
	var root:Float;
	var nearest:Float;
	var levels:LevelSet;
	var pivots:PivotMarkSet;
	var labels:LabelSet;
	var rings:RingBag;
}

class SquareOfNineIndicator implements MuseIndicator<Bar, SquareOfNineOutput> {
	var swing:SwingGraph;
	var step:Float;
	var out:SquareOfNineOutput;

	public function new(?threshold:Float, ?step:Float) {
		swing = new SwingGraph(threshold != null ? threshold : 0.05, 4);
		this.step = step != null && step > 0 ? step : Math.NaN;
		out = {
			root: Math.NaN, nearest: Math.NaN,
			levels: LevelSet.nan(), pivots: PivotMarkSet.nan(), labels: LabelSet.nan(), rings: RingBag.nan()
		};
	}

	public function update(bar:Bar):Null<SquareOfNineOutput> {
		swing.update(bar);
		if (swing.pivotCount() < 1) return null;
		var root = swing.pivotAt(swing.pivotCount() - 1).price;
		var step = Math.isFinite(this.step) ? this.step : Math.abs(root) * 0.01;
		out.root = root;
		var near = SquareOfNine.nearest(root, bar.close, 4, step);
		out.nearest = near.price;
		var st = GeomVizFill.statusOf(PivotStatus.Projected);
		var conf = GeomVizFill.statusOf(PivotStatus.Confirmed);
		out.levels.clear();
		out.rings.clear();
		out.rings.setCenter(root, conf);
		var n = 0;
		for (ring in 1...5) {
			if (n >= LevelSet.CAP) break;
			var up = SquareOfNine.priceAt(root, ring, 0, step);
			var dn = root - (up - root);
			out.levels.set(n, up, ring * 1.0, st);
			if (n < RingBag.CAP) out.rings.setPrice(n, up);
			n++;
			if (n >= LevelSet.CAP) break;
			out.levels.set(n, dn, (-ring) * 1.0, st);
			if (n < RingBag.CAP) out.rings.setPrice(n, dn);
			n++;
		}
		out.levels.count = n * 1.0;
		out.rings.count = n * 1.0;
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 2);
		out.labels.clear();
		out.labels.set(0, (GeomLabelCode.Projected : Int) * 1.0, near.price, swing.currentBar() * 1.0, st);
		out.labels.count = 1;
		return out;
	}

	public function reset():Void {
		swing.reset();
		out.levels.clear(); out.pivots.clear(); out.labels.clear(); out.rings.clear();
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return swing.pivotCount() >= 1;
	public function name():String return "SquareOfNine";

	public static function spec():IndicatorSpec {
		return {
			name: "square_of_nine", args: [TScalar, TScalar], ret: TObject([
				{name: "root", ty: TScalar}, {name: "nearest", ty: TScalar},
				{name: "levels", ty: GeomVizSpec.levelObj()},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "labels", ty: GeomVizSpec.labelObj()},
				{name: "rings", ty: GeomVizSpec.ringObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var thr = IndicatorCache.floatArg(args, 0, 0.05);
				var step = IndicatorCache.floatArg(args, 1, Math.NaN);
				var nanFill:SquareOfNineOutput = {
					root: Math.NaN, nearest: Math.NaN,
					levels: LevelSet.nan(), pivots: PivotMarkSet.nan(), labels: LabelSet.nan(), rings: RingBag.nan()
				};
				return IndicatorCache.evalBar(h, 'square_of_nine:$thr:$step', nanFill,
					() -> new SquareOfNineIndicator(thr, Math.isFinite(step) ? step : null),
					(i, b) -> (cast i : SquareOfNineIndicator).update(b));
			}
		};
	}
}
