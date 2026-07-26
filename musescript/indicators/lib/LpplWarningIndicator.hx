package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.PivotStatus;
import musescript.indicators.offline.OfflineHooks;
import musescript.types.MuseType;

/**
 * Streaming LPPL heuristic warning facade (GEOM_RISK).
 * Uses OfflineHooks.LpplFit on a trailing window — NOT inside EwProject.
 * Emits forecast band + zone tagged Projected for chart ribbon binding.
 */
typedef LpplWarningOutput = {
	var warning:Float;
	var residual:Float;
	var tc:Float;
	var zones:ZoneSet;
	var forecast:ForecastBand;
	var labels:LabelSet;
}

class LpplWarningIndicator implements MuseIndicator<Bar, LpplWarningOutput> {
	var period:Int;
	var closes:RingBuffer<Float>;
	var scratch:haxe.ds.Vector<Float>;
	var scratchLen:Int;
	var out:LpplWarningOutput;
	var barsSeen:Int;

	public function new(period:Int = 40) {
		if (period < 30) throw "LpplWarningIndicator: period must be >= 30";
		this.period = period;
		closes = new RingBuffer(period);
		scratch = new haxe.ds.Vector<Float>(period);
		scratchLen = 0;
		barsSeen = 0;
		out = {
			warning: Math.NaN, residual: Math.NaN, tc: Math.NaN,
			zones: ZoneSet.nan(), forecast: ForecastBand.nan(), labels: LabelSet.nan()
		};
	}

	public function update(bar:Bar):Null<LpplWarningOutput> {
		barsSeen++;
		closes.push(bar.close);
		if (closes.length < period) return null;
		// Oldest→newest into fixed scratch (no Array realloc on hot path)
		scratchLen = closes.length;
		for (i in 0...scratchLen) scratch[i] = closes.at(scratchLen - 1 - i);
		var fit = LpplFit.fitWarningVec(scratch, scratchLen);
		out.warning = fit.warning ? 1.0 : 0.0;
		out.residual = fit.residual;
		out.tc = fit.tc;
		var st = GeomVizFill.statusOf(PivotStatus.Projected);
		var now = (barsSeen - 1) * 1.0;
		var lo = bar.close * (fit.warning ? 0.98 : 0.995);
		var hi = bar.close * (fit.warning ? 1.08 : 1.005);
		out.forecast.set(lo, hi, now, now + 10);
		out.zones.clear();
		out.zones.set(0, lo, hi, now, now + 10, st, (ZoneKind.Forecast : Int) * 1.0);
		out.zones.count = 1;
		out.labels.clear();
		out.labels.set(0, (GeomLabelCode.Projected : Int) * 1.0, hi, now + 5, st);
		out.labels.count = 1;
		return out;
	}

	public function reset():Void {
		closes = new RingBuffer(period);
		barsSeen = 0;
		scratchLen = 0;
		out.zones.clear(); out.forecast.clear(); out.labels.clear();
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return closes.length == period;
	public function name():String return "LpplWarning";

	public static function spec():IndicatorSpec {
		return {
			name: "lppl_warning", args: [TWindow], ret: TObject([
				{name: "warning", ty: TScalar}, {name: "residual", ty: TScalar}, {name: "tc", ty: TScalar},
				{name: "zones", ty: GeomVizSpec.zoneObj()},
				{name: "forecast", ty: GeomVizSpec.forecastObj()},
				{name: "labels", ty: GeomVizSpec.labelObj()}
			]), minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 40);
				var nanFill:LpplWarningOutput = {
					warning: Math.NaN, residual: Math.NaN, tc: Math.NaN,
					zones: ZoneSet.nan(), forecast: ForecastBand.nan(), labels: LabelSet.nan()
				};
				return IndicatorCache.evalBar(h, "lppl_warning:" + p, nanFill,
					() -> new LpplWarningIndicator(p), (i, b) -> (cast i : LpplWarningIndicator).update(b));
			}
		};
	}
}
