package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

typedef SsaCyclesOutput = {
	var cycleBars:Float;
	var phase:Float;
	var strength:Float;
	var zones:ZoneSet;
	var labels:LabelSet;
	var forecast:ForecastBand;
}

/** SSA-lite cycle estimator with TimeWindow zones for chart binding. */
class SsaCycles implements MuseIndicator<Bar, SsaCyclesOutput> {
	var period:Int;
	var minLag:Int;
	var maxLag:Int;
	var window:RingBuffer<Float>;
	var out:SsaCyclesOutput;
	var barsSeen:Int;

	public function new(period:Int = 64, minLag:Int = 4, maxLag:Int = 32) {
		if (period < 16) throw "SsaCycles: period must be >= 16";
		if (minLag < 2 || maxLag <= minLag || maxLag >= period)
			throw "SsaCycles: require 2 <= minLag < maxLag < period";
		this.period = period;
		this.minLag = minLag;
		this.maxLag = maxLag;
		window = new RingBuffer(period);
		barsSeen = 0;
		out = {
			cycleBars: Math.NaN, phase: Math.NaN, strength: Math.NaN,
			zones: ZoneSet.nan(), labels: LabelSet.nan(), forecast: ForecastBand.nan()
		};
	}

	public function update(bar:Bar):Null<SsaCyclesOutput> {
		barsSeen++;
		window.push(bar.close);
		if (window.length < period) return null;

		var mean = 0.0;
		for (i in 0...window.length) mean += window.at(i);
		mean /= window.length;

		var bestLag = minLag;
		var bestAbs = 0.0;
		for (lag in minLag...maxLag + 1) {
			var num = 0.0; var d0 = 0.0; var d1 = 0.0;
			var n = window.length - lag;
			for (i in 0...n) {
				var x = window.at(window.length - 1 - i) - mean;
				var y = window.at(window.length - 1 - (i + lag)) - mean;
				num += x * y; d0 += x * x; d1 += y * y;
			}
			var den = Math.sqrt(d0 * d1);
			var corr = den > 0 ? num / den : 0.0;
			var ac = Math.abs(corr);
			if (ac > bestAbs) { bestAbs = ac; bestLag = lag; }
		}

		var newest = window.at(0) - mean;
		var lagged = window.at(bestLag) - mean;
		out.cycleBars = bestLag * 1.0;
		out.phase = Math.atan2(newest, lagged + 1e-12);
		out.strength = bestAbs;

		var st = GeomVizFill.statusOf(PivotStatus.Projected);
		var now = (barsSeen - 1) * 1.0;
		var band = Math.abs(bar.close) * 0.002;
		if (!(band > 0)) band = 0.01;
		out.zones.clear();
		for (k in 1...ZoneSet.CAP + 1) {
			var b = now + k * bestLag;
			out.zones.set(k - 1, bar.close - band, bar.close + band, b, b, st, (ZoneKind.Cycle : Int) * 1.0);
		}
		out.zones.count = ZoneSet.CAP * 1.0;
		out.labels.clear();
		out.labels.set(0, (GeomLabelCode.Projected : Int) * 1.0, bar.close, now + bestLag, st);
		out.labels.count = 1;
		out.forecast.set(bar.close * 0.99, bar.close * 1.01, now, now + bestLag);
		return out;
	}

	public function reset():Void {
		window = new RingBuffer(period);
		barsSeen = 0;
		out.zones.clear(); out.labels.clear(); out.forecast.clear();
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "SsaCycles";

	public static function spec():IndicatorSpec {
		return {
			name: "ssa_cycles", args: [TWindow, TWindow, TWindow], ret: TObject([
				{name: "cycleBars", ty: TScalar}, {name: "phase", ty: TScalar}, {name: "strength", ty: TScalar},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "labels", ty: GeomVizSpec.labelObj()},
				{name: "forecast", ty: GeomVizSpec.forecastObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 64);
				var lo = IndicatorCache.intArg(args, 1, 4);
				var hi = IndicatorCache.intArg(args, 2, Std.int(Math.min(32, p - 1)));
				var nanFill:SsaCyclesOutput = {
					cycleBars: Math.NaN, phase: Math.NaN, strength: Math.NaN,
					zones: ZoneSet.nan(), labels: LabelSet.nan(), forecast: ForecastBand.nan()
				};
				return IndicatorCache.evalBar(h, 'ssa_cycles:$p:$lo:$hi', nanFill,
					() -> new SsaCycles(p, lo, hi), (i, b) -> (cast i : SsaCycles).update(b));
			}
		};
	}
}
