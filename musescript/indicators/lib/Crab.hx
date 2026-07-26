package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.geom.HarmonicHost;
import musescript.indicators.geom.GeomViz;
import musescript.indicators.geom.HarmonicVizEmit;
import musescript.indicators.geom.PivotStatus;
import musescript.types.MuseType;

class Crab implements MuseIndicator<Bar, HarmonicVizOutput> {
	static final WINDOWS = {
		abXaLo: 0.382, abXaHi: 0.618,
		bcAbLo: 0.382, bcAbHi: 0.886,
		cdBcLo: 2.24, cdBcHi: 3.618,
		adXaLo: 1.55, adXaHi: 1.65
	};
	var host:HarmonicHost;
	var hasEmitted:Bool;
	var out:HarmonicVizOutput;

	public function new() {
		host = new HarmonicHost(0.05, 5);
		hasEmitted = false;
		out = HarmonicVizEmit.nanOut();
		out.signal = 0; out.przStrength = 0;
	}

	public function update(candle:Bar):Null<HarmonicVizOutput> {
		hasEmitted = true;
		HarmonicVizEmit.fill(host, host.update(candle), WINDOWS, out);
		return out;
	}

	public function reset():Void {
		host.reset(); hasEmitted = false;
		out.signal = 0; out.prz = Math.NaN; out.przStrength = 0;
		out.levels.clear(); out.zones.clear(); out.pivots.clear(); out.labels.clear();
	}

	public function warmupPeriod():Int return 6;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Crab";

	public static function spec():IndicatorSpec {
		return {
			name: "crab", args: [], ret: TObject(HarmonicVizEmit.specFields()), minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "crab", HarmonicVizEmit.nanOut(),
				() -> new Crab(), (i, b) -> (cast i : Crab).update(b))
		};
	}
}
