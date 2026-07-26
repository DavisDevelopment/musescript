package musescript.indicators.geom;

import musescript.types.MuseType;
import musescript.indicators.geom.GeomViz; // LevelSet, ZoneSet, GeomVizFill, ZoneKind, GeomLabelCode, …
import musescript.indicators.geom.HarmonicHost; // HarmonicHost, HarmonicWindows, HarmonicMatch
import musescript.indicators.geom.PivotStatus;

/**
 * Stable harmonic chart TObject — signal + PRZ + XABCD viz packs.
 * Own module so libs can `import musescript.indicators.geom.HarmonicVizEmit`.
 * Viz slot types (LevelSet, …) live in GeomViz.hx — imported below.
 */
typedef HarmonicVizOutput = {
	var signal:Float;
	var prz:Float;
	var przStrength:Float;
	var levels:LevelSet;
	var zones:ZoneSet;
	var pivots:PivotMarkSet;
	var labels:LabelSet;
}

class HarmonicVizEmit {
	public static function fill(host:HarmonicHost, confirmed:Bool, windows:HarmonicWindows, out:HarmonicVizOutput):Void {
		out.signal = 0;
		out.prz = Math.NaN;
		out.przStrength = 0;
		out.levels.clear();
		out.zones.clear();
		GeomVizFill.pivotsFromGraph(host.graph(), out.pivots, 5);
		GeomVizFill.xabcdLabels(host.graph(), out.labels);
		if (!confirmed) return;

		var m = host.matchXabcd(windows);
		out.signal = m.signal;
		out.prz = m.prz;
		out.przStrength = m.przStrength;
		if (!Math.isFinite(m.prz)) return;

		var half = Math.abs(m.prz) * 0.01;
		var st = m.signal != 0
			? GeomVizFill.statusOf(PivotStatus.Confirmed)
			: GeomVizFill.statusOf(PivotStatus.Projected);
		out.levels.set(0, m.prz, 0.786, st);
		out.levels.count = 1;
		var bar = host.graph().currentBar() * 1.0;
		out.zones.set(0, m.prz - half, m.prz + half, bar, bar + 5, st, (ZoneKind.Prz : Int) * 1.0);
		out.zones.count = 1;
		out.labels.set(5, (GeomLabelCode.PrzLabel : Int) * 1.0, m.prz, bar, st);
		if (out.labels.count < 6) out.labels.count = 6;
	}

	public static function nanOut():HarmonicVizOutput {
		return {
			signal: Math.NaN, prz: Math.NaN, przStrength: Math.NaN,
			levels: LevelSet.nan(), zones: ZoneSet.nan(),
			pivots: PivotMarkSet.nan(), labels: LabelSet.nan()
		};
	}

	public static function specFields():Array<{name:String, ty:MuseType}> {
		return [
			{name: "signal", ty: TScalar}, {name: "prz", ty: TScalar}, {name: "przStrength", ty: TScalar},
			{name: "levels", ty: GeomVizSpec.levelObj()},
			{name: "zones", ty: GeomVizSpec.zoneObj()},
			{name: "pivots", ty: GeomVizSpec.pivotObj()},
			{name: "labels", ty: GeomVizSpec.labelObj()}
		];
	}
}
