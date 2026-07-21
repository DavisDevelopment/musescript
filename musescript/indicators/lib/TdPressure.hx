package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Pressure — ported from wickra-core's `TdPressure`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_pressure.rs).
 *
 * Volume-weighted buying / selling pressure oscillator bounded in ±100:
 *   bar_pressure(i) = ((close - open) / (high - low)) * volume  (0 if range == 0)
 *   TD_Pressure = 100 * SMA(bar_pressure, period) / SMA(volume, period)
 * A flat zero-volume window emits 0.
 */
class TdPressure implements MuseIndicator<Bar, Float> {
	var period:Int;
	var pressures:Array<Float>;
	var volumes:Array<Float>;
	var lastValue:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "TdPressure: period must be > 0";
		this.period = period;
		reset();
	}

	/** Configured window. */
	public function getPeriod():Int return period;

	/** Latest emitted value if available. */
	public function value():Null<Float> return lastValue;

	public function update(bar:Bar):Null<Float> {
		var range = bar.high - bar.low;
		var barPressure = range > 0.0 ? ((bar.close - bar.open) / range) * bar.volume : 0.0;

		if (pressures.length == period) {
			pressures.shift();
			volumes.shift();
		}
		pressures.push(barPressure);
		volumes.push(bar.volume);
		if (pressures.length < period) return null;
		var n:Float = period;
		var sumP = 0.0, sumV = 0.0;
		for (v in pressures) sumP += v;
		for (v in volumes) sumV += v;
		var meanP = sumP / n;
		var meanV = sumV / n;
		var v = meanV == 0.0 ? 0.0 : 100.0 * meanP / meanV;
		lastValue = v;
		return v;
	}

	public function reset():Void {
		pressures = [];
		volumes = [];
		lastValue = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return lastValue != null;
	public function name():String return "TDPressure";

	public static function spec():IndicatorSpec {
		return {
			name: "td_pressure", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 5);
				return IndicatorCache.evalBar(h, "td_pressure:" + p, Math.NaN,
					() -> new TdPressure(p), (i, b) -> (cast i : TdPressure).update(b));
			}
		};
	}
}
