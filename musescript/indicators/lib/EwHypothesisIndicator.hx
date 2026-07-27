package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.ew.EwLattice;
import musescript.indicators.ew.EwProject;
import musescript.indicators.ew.DowTrendFilter;
import musescript.indicators.geom.SwingGraph;
import musescript.indicators.geom.SwingGraphStack;
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
	/** Relative degree of top hypothesis (0=fine, 1=coarse). */
	var degree:Float;
	/** Parent coarse label code when nested; 0 if none. */
	var parentLabelCode:Float;
	/** Soft nesting score for top hypothesis (1.0 = neutral). */
	var nestScore:Float;
	var parentStartBar:Float;
	var parentEndBar:Float;
	/** Count-kill price for top hypothesis (NaN if N/A). */
	var invalidatePrice:Float;
	/** Bar of invalidatePrice pivot (NaN if N/A). */
	var invalidateBar:Float;
	var pivots:PivotMarkSet;
	var labels:LabelSet;
	var forecast:ForecastBand;
	var zones:ZoneSet;
}

class EwHypothesisIndicator implements MuseIndicator<Bar, EwHypothesisOutput> {
	var stack:SwingGraphStack;
	var lattice:EwLattice;
	var out:EwHypothesisOutput;
	var k:Int;

	public function new(?threshold:Float, k:Int = 3) {
		var fine = threshold != null ? threshold : 0.05;
		stack = new SwingGraphStack(fine, null, 12);
		lattice = new EwLattice();
		this.k = k < 1 ? 1 : k;
		out = {
			labelCode: 0, topScore: Math.NaN, hypCount: 0,
			startBar: Math.NaN, endBar: Math.NaN, waveCount: 0, dowBias: 0,
			degree: 0, parentLabelCode: 0, nestScore: 1.0,
			parentStartBar: Math.NaN, parentEndBar: Math.NaN,
			invalidatePrice: Math.NaN, invalidateBar: Math.NaN,
			pivots: PivotMarkSet.nan(), labels: LabelSet.nan(),
			forecast: ForecastBand.nan(), zones: ZoneSet.nan()
		};
	}

	static function labelCodeOf(label:String):Float {
		return switch (label) {
			case "zigzag": 1.0;
			case "impulse5": 2.0;
			case "flat", "flat_expanded", "flat_running": 3.0;
			case "diagonal", "diagonal_ending": 4.0;
			case "triangle": 5.0;
			case "double_zigzag": 6.0;
			case "diagonal_leading": 7.0;
			case "impulse5_trunc": 8.0;
			case "impulse5_ext1": 9.0;
			case "impulse5_ext3": 10.0;
			case "impulse5_ext5": 11.0;
			case "double_three": 12.0;
			case "triangle_expanding": 13.0;
			default: 0.0;
		};
	}

	public function update(bar:Bar):Null<EwHypothesisOutput> {
		stack.update(bar);
		var n = lattice.rebuildStack(stack, k);
		GeomVizFill.pivotsFromGraph(stack.fine, out.pivots, 8);
		out.labels.clear();
		out.zones.clear();
		out.forecast.clear();
		out.dowBias = (DowTrendFilter.bias(stack.fine) : Int) * 1.0;

		if (n == 0) {
			out.labelCode = 0; out.topScore = 0; out.hypCount = 0;
			out.startBar = Math.NaN; out.endBar = Math.NaN; out.waveCount = 0;
			out.degree = 0; out.parentLabelCode = 0; out.nestScore = 1.0;
			out.parentStartBar = Math.NaN; out.parentEndBar = Math.NaN;
			out.invalidatePrice = Math.NaN; out.invalidateBar = Math.NaN;
			return out;
		}
		var top = lattice.at(0);
		out.labelCode = labelCodeOf(top.label);
		out.topScore = top.score;
		out.hypCount = n * 1.0;
		out.startBar = top.startBar * 1.0;
		out.endBar = top.endBar * 1.0;
		out.waveCount = top.waveCount * 1.0;
		out.degree = top.degree * 1.0;
		out.nestScore = top.nestScore;
		out.parentStartBar = top.parentStartBar >= 0 ? top.parentStartBar * 1.0 : Math.NaN;
		out.parentEndBar = top.parentEndBar >= 0 ? top.parentEndBar * 1.0 : Math.NaN;
		out.invalidatePrice = top.invalidatePrice;
		out.invalidateBar = top.invalidateBar;
		if (top.parentHypothesisId >= 0 && top.parentHypothesisId < lattice.coarseHypothesisCount()) {
			out.parentLabelCode = labelCodeOf(lattice.coarseAt(top.parentHypothesisId).label);
		} else {
			out.parentLabelCode = 0;
		}

		var waveCodes = switch (top.label) {
			case "impulse5", "impulse5_trunc", "impulse5_ext1", "impulse5_ext3", "impulse5_ext5",
				"diagonal", "diagonal_ending", "diagonal_leading":
				[GeomLabelCode.Wave1, GeomLabelCode.Wave2, GeomLabelCode.Wave3, GeomLabelCode.Wave4, GeomLabelCode.Wave5];
			case "triangle", "triangle_expanding":
				[GeomLabelCode.WaveA, GeomLabelCode.WaveB, GeomLabelCode.WaveC, GeomLabelCode.WaveA, GeomLabelCode.WaveB];
			case "double_zigzag", "double_three":
				[GeomLabelCode.WaveA, GeomLabelCode.WaveB, GeomLabelCode.WaveC, GeomLabelCode.X,
					GeomLabelCode.WaveA, GeomLabelCode.WaveB, GeomLabelCode.WaveC];
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
		if (band == null) band = EwProject.fromLastLeg(stack.fine);
		if (band != null) {
			out.forecast.set(band.priceLo, band.priceHi, band.barLo, band.barHi);
			out.zones.set(0, band.priceLo, band.priceHi, band.barLo, band.barHi,
				GeomVizFill.statusOf(PivotStatus.Projected), (ZoneKind.Forecast : Int) * 1.0);
			out.zones.count = 1;
		}

		// Thin projected invalidation level (trailing zone slot; shape-stable).
		if (Math.isFinite(top.invalidatePrice)) {
			var ziInv = Std.int(out.zones.count);
			if (ziInv < ZoneSet.CAP) {
				var inv = top.invalidatePrice;
				var pad = Math.max(1e-9, Math.abs(inv) * 1e-6);
				var bar0 = Math.isFinite(top.invalidateBar) ? top.invalidateBar : top.endBar * 1.0;
				var bar1 = top.endBar * 1.0;
				if (!(bar1 >= bar0)) bar1 = bar0 + 1;
				out.zones.set(ziInv, inv - pad, inv + pad, bar0, bar1,
					GeomVizFill.statusOf(PivotStatus.Projected), (ZoneKind.Invalidation : Int) * 1.0);
				out.zones.count = (ziInv + 1) * 1.0;
			}
		}

		// Parent degree overlay: coarse span zone + pattern glyph (Forming = dashed/muted).
		// Convention: ZoneKind.ParentDegree; Impulse/Zigzag label codes mark the parent (not fine waves).
		if (top.parentHypothesisId >= 0
			&& Math.isFinite(out.parentStartBar) && Math.isFinite(out.parentEndBar)) {
			var parent = lattice.coarseAt(top.parentHypothesisId);
			var cs = lattice.coarseScratchVec();
			var o = parent.offset;
			var plo = Math.POSITIVE_INFINITY;
			var phi = Math.NEGATIVE_INFINITY;
			for (i in 0...parent.waveCount) {
				if (o + i >= cs.length) break;
				var pr = cs[o + i].price;
				if (pr < plo) plo = pr;
				if (pr > phi) phi = pr;
			}
			if (plo < Math.POSITIVE_INFINITY && phi > Math.NEGATIVE_INFINITY) {
				var zi = Std.int(out.zones.count);
				if (zi < ZoneSet.CAP) {
					out.zones.set(zi, plo, phi, out.parentStartBar, out.parentEndBar,
						GeomVizFill.statusOf(PivotStatus.Forming), (ZoneKind.ParentDegree : Int) * 1.0);
					out.zones.count = (zi + 1) * 1.0;
				}
				var li = Std.int(out.labels.count);
				if (li < LabelSet.CAP) {
					var pCode = switch (Std.int(out.parentLabelCode)) {
						case 1, 3, 5, 6: GeomLabelCode.Zigzag;
						default: GeomLabelCode.Impulse;
					};
					var midBar = (out.parentStartBar + out.parentEndBar) * 0.5;
					var midPrice = (plo + phi) * 0.5;
					out.labels.set(li, (pCode : Int) * 1.0, midPrice, midBar,
						GeomVizFill.statusOf(PivotStatus.Forming));
					out.labels.count = (li + 1) * 1.0;
				}
			}
		}
		return out;
	}

	public function reset():Void {
		stack.reset();
		out.pivots.clear(); out.labels.clear(); out.forecast.clear(); out.zones.clear();
	}

	public function warmupPeriod():Int return 8;
	public function isReady():Bool return stack.fine.pivotCount() >= 4;
	public function name():String return "EwHypothesis";

	public static function spec():IndicatorSpec {
		return {
			name: "ew_hypothesis", args: [TScalar], ret: TObject([
				{name: "labelCode", ty: TScalar}, {name: "topScore", ty: TScalar}, {name: "hypCount", ty: TScalar},
				{name: "startBar", ty: TScalar}, {name: "endBar", ty: TScalar}, {name: "waveCount", ty: TScalar},
				{name: "dowBias", ty: TScalar},
				{name: "degree", ty: TScalar}, {name: "parentLabelCode", ty: TScalar},
				{name: "nestScore", ty: TScalar}, {name: "parentStartBar", ty: TScalar}, {name: "parentEndBar", ty: TScalar},
				{name: "invalidatePrice", ty: TScalar}, {name: "invalidateBar", ty: TScalar},
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
					degree: Math.NaN, parentLabelCode: Math.NaN, nestScore: Math.NaN,
					parentStartBar: Math.NaN, parentEndBar: Math.NaN,
					invalidatePrice: Math.NaN, invalidateBar: Math.NaN,
					pivots: PivotMarkSet.nan(), labels: LabelSet.nan(),
					forecast: ForecastBand.nan(), zones: ZoneSet.nan()
				};
				return IndicatorCache.evalBar(h, "ew_hypothesis:" + t, nanFill,
					() -> new EwHypothesisIndicator(t), (i, b) -> (cast i : EwHypothesisIndicator).update(b));
			}
		};
	}
}
