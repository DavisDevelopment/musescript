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

class Shark implements MuseIndicator<Bar, HarmonicVizOutput> {
	static final WINDOWS = {
		abXaLo: 1.13, abXaHi: 1.618,
		bcAbLo: 1.618, bcAbHi: 2.24,
		cdBcLo: 0.382, cdBcHi: 0.886,
		adXaLo: 0.886, adXaHi: 1.13
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
	public function name():String return "Shark";

	public static function spec():IndicatorSpec {
		return {
			name: "shark", args: [], ret: TObject(HarmonicVizEmit.specFields()), minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "shark", HarmonicVizEmit.nanOut(),
				() -> new Shark(), (i, b) -> (cast i : Shark).update(b))
		};
	}
}
