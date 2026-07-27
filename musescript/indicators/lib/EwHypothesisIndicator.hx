package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.ew.EwLattice;
import musescript.indicators.ew.EwProject;
import musescript.indicators.ew.DowTrendFilter;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

/**
 * EW hypothesis + projection cone + Dow bias — chart-rich lattice facade.
 * labelCode: 0=none, 1=zigzag, 2=impulse5
 * dowBias: -1/0/+1
 */
typedef EwHypothesisOutput = {
	var labelCode:Float;
	var topScore:Float;
	var hypCount:Float;
	var startBar:Float;
	var endBar:Float;
	var waveCount:Float;
	var dowBias:Float;
	var pivots:PivotMarkSet;
	var labels:LabelSet;
	var forecast:ForecastBand;
	var zones:ZoneSet;
}

class EwHypothesisIndicator implements MuseIndicator<Bar, EwHypothesisOutput> {
	var swing:SwingGraph;
	var lattice:EwLattice;
	var out:EwHypothesisOutput;
	var k:Int;

	public function new(?threshold:Float, k:Int = 3) {
		swing = new SwingGraph(threshold != null ? threshold : 0.05, 12);
		lattice = new EwLattice();
		this.k = k < 1 ? 1 : k;
		out = {
			labelCode: 0, topScore: Math.NaN, hypCount: 0,
			startBar: Math.NaN, endBar: Math.NaN, waveCount: 0, dowBias: 0,
			pivots: PivotMarkSet.nan(), labels: LabelSet.nan(),
			forecast: ForecastBand.nan(), zones: ZoneSet.nan()
		};
	}

	static function labelCodeOf(label:String):Float {
		return switch (label) {
			case "zigzag": 1.0;
			case "impulse5": 2.0;
			case "flat": 3.0;
			case "diagonal": 4.0;
			case "triangle": 5.0;
			default: 0.0;
		};
	}

	public function update(bar:Bar):Null<EwHypothesisOutput> {
		swing.update(bar);
		var n = lattice.rebuild(swing, k);
		GeomVizFill.pivotsFromGraph(swing, out.pivots, 8);
		out.labels.clear();
		out.zones.clear();
		out.forecast.clear();
		out.dowBias = (DowTrendFilter.bias(swing) : Int) * 1.0;

		if (n == 0) {
			out.labelCode = 0; out.topScore = 0; out.hypCount = 0;
			out.startBar = Math.NaN; out.endBar = Math.NaN; out.waveCount = 0;
			return out;
		}
		var top = lattice.at(0);
		out.labelCode = labelCodeOf(top.label);
		out.topScore = top.score;
		out.hypCount = n * 1.0;
		out.startBar = top.startBar * 1.0;
		out.endBar = top.endBar * 1.0;
		out.waveCount = top.waveCount * 1.0;

		var waveCodes = switch (top.label) {
			case "impulse5", "diagonal":
				[GeomLabelCode.Wave1, GeomLabelCode.Wave2, GeomLabelCode.Wave3, GeomLabelCode.Wave4, GeomLabelCode.Wave5];
			case "triangle":
				[GeomLabelCode.WaveA, GeomLabelCode.WaveB, GeomLabelCode.WaveC, GeomLabelCode.WaveA, GeomLabelCode.WaveB];
			default:
				[GeomLabelCode.WaveA, GeomLabelCode.WaveB, GeomLabelCode.WaveC];
		};
		var take = Std.int(Math.min(waveCodes.length, out.pivots.count));
		var pStart = Std.int(out.pivots.count) - take;
		if (pStart < 0) pStart = 0;
		for (i in 0...take) {
			var pi = pStart + i;
			var price = switch (pi) {
				case 0: out.pivots.p0; case 1: out.pivots.p1; case 2: out.pivots.p2;
				case 3: out.pivots.p3; case 4: out.pivots.p4; case 5: out.pivots.p5;
				case 6: out.pivots.p6; default: out.pivots.p7;
			};
			var b = switch (pi) {
				case 0: out.pivots.b0; case 1: out.pivots.b1; case 2: out.pivots.b2;
				case 3: out.pivots.b3; case 4: out.pivots.b4; case 5: out.pivots.b5;
				case 6: out.pivots.b6; default: out.pivots.b7;
			};
			out.labels.set(i, (waveCodes[i] : Int) * 1.0, price, b, GeomVizFill.statusOf(PivotStatus.Confirmed));
		}
		out.labels.count = take * 1.0;

		var band = EwProject.fromHypothesis(top, lattice.scratch());
		if (band == null) band = EwProject.fromLastLeg(swing);
		if (band != null) {
			out.forecast.set(band.priceLo, band.priceHi, band.barLo, band.barHi);
			out.zones.set(0, band.priceLo, band.priceHi, band.barLo, band.barHi,
				GeomVizFill.statusOf(PivotStatus.Projected), (ZoneKind.Forecast : Int) * 1.0);
			out.zones.count = 1;
		}
		return out;
	}

	public function reset():Void {
		swing.reset();
		out.pivots.clear(); out.labels.clear(); out.forecast.clear(); out.zones.clear();
	}

	public function warmupPeriod():Int return 8;
	public function isReady():Bool return swing.pivotCount() >= 4;
	public function name():String return "EwHypothesis";

	public static function spec():IndicatorSpec {
		return {
			name: "ew_hypothesis", args: [TScalar], ret: TObject([
				{name: "labelCode", ty: TScalar}, {name: "topScore", ty: TScalar}, {name: "hypCount", ty: TScalar},
				{name: "startBar", ty: TScalar}, {name: "endBar", ty: TScalar}, {name: "waveCount", ty: TScalar},
				{name: "dowBias", ty: TScalar},
				{name: "pivots", ty: GeomVizSpec.pivotObj()},
				{name: "labels", ty: GeomVizSpec.labelObj()},
				{name: "forecast", ty: GeomVizSpec.forecastObj()},
				{name: "zones", ty: GeomVizSpec.zoneObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var t = IndicatorCache.floatArg(args, 0, 0.05);
				var nanFill:EwHypothesisOutput = {
					labelCode: Math.NaN, topScore: Math.NaN, hypCount: Math.NaN,
					startBar: Math.NaN, endBar: Math.NaN, waveCount: Math.NaN, dowBias: Math.NaN,
					pivots: PivotMarkSet.nan(), labels: LabelSet.nan(),
					forecast: ForecastBand.nan(), zones: ZoneSet.nan()
				};
				return IndicatorCache.evalBar(h, "ew_hypothesis:" + t, nanFill,
					() -> new EwHypothesisIndicator(t), (i, b) -> (cast i : EwHypothesisIndicator).update(b));
			}
		};
	}
}
