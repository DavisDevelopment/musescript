package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.HarmonicVizEmit;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

/** Cypher — custom XC ratios; same HarmonicVizOutput chart contract. */
class Cypher implements MuseIndicator<Bar, HarmonicVizOutput> {
	var swing:SwingGraph;
	var hasEmitted:Bool;
	var out:HarmonicVizOutput;

	public function new() {
		swing = new SwingGraph(0.05, 5);
		hasEmitted = false;
		out = HarmonicVizEmit.nanOut();
		out.signal = 0; out.przStrength = 0;
	}

	public function update(candle:Bar):Null<HarmonicVizOutput> {
		hasEmitted = true;
		var confirmed = swing.update(candle);
		out.signal = 0;
		out.prz = Math.NaN;
		out.przStrength = 0;
		out.levels.clear();
		out.zones.clear();
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 5);
		GeomVizFill.xabcdLabels(swing, out.labels);
		if (!confirmed || swing.pivotCount() < 5) return out;

		var n = swing.pivotCount();
		var px = swing.pivotAt(n - 5).price;
		var pa = swing.pivotAt(n - 4).price;
		var pb = swing.pivotAt(n - 3).price;
		var pc = swing.pivotAt(n - 2).price;
		var pd = swing.pivotAt(n - 1);
		var xa = Math.abs(pa - px);
		var ab = Math.abs(pb - pa);
		var bc = Math.abs(pc - pb);
		var xc = Math.abs(pc - px);
		var cd = Math.abs(pd.price - pc);
		if (xa <= 0 || xc <= 0) return out;

		var matched = ab / xa >= 0.382 && ab / xa <= 0.618
			&& bc / xa >= 1.13 && bc / xa <= 1.414
			&& cd / xc >= 0.74 && cd / xc <= 0.83;
		if (matched) out.signal = pd.direction < 0.0 ? 1.0 : -1.0;

		// PRZ ≈ 0.786 of XC from C
		var dir = pc >= px ? -1.0 : 1.0;
		var prz = pc + dir * 0.786 * xc;
		out.prz = prz;
		out.przStrength = matched ? 1.0 : 0.5;
		var st = matched ? GeomVizFill.statusOf(PivotStatus.Confirmed) : GeomVizFill.statusOf(PivotStatus.Projected);
		var half = Math.abs(prz) * 0.01;
		var bar = swing.currentBar() * 1.0;
		out.levels.set(0, prz, 0.786, st);
		out.levels.count = 1;
		out.zones.set(0, prz - half, prz + half, bar, bar + 5, st, (ZoneKind.Prz : Int) * 1.0);
		out.zones.count = 1;
		out.labels.set(5, (GeomLabelCode.PrzLabel : Int) * 1.0, prz, bar, st);
		if (out.labels.count < 6) out.labels.count = 6;
		return out;
	}

	public function reset():Void {
		swing.reset(); hasEmitted = false;
		out.signal = 0; out.prz = Math.NaN; out.przStrength = 0;
		out.levels.clear(); out.zones.clear(); out.pivots.clear(); out.labels.clear();
	}

	public function warmupPeriod():Int return 6;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Cypher";

	public static function spec():IndicatorSpec {
		return {
			name: "cypher", args: [], ret: TObject(HarmonicVizEmit.specFields()), minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "cypher", HarmonicVizEmit.nanOut(),
				() -> new Cypher(), (i, b) -> (cast i : Cypher).update(b))
		};
	}
}
