package musescript.indicators;

import musescript.harness.Bar;

/**
 * Commodity Channel Index — ported from wickra-core's `Cci`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/cci.rs).
 *
 * `CCI = (TP - SMA(TP)) / (0.015 * mean absolute deviation of TP)`, where
 * `TP = (high + low + close) / 3`. A zero-deviation window (every TP equal)
 * returns 0 rather than dividing by zero.
 */
class Cci implements MuseIndicator<Bar, Float> {
	var period:Int;
	var factor:Float;
	var window:Array<Float>;
	var sum:Float;

	/** `factor` defaults to the canonical 0.015 (puts ~70% of values inside +/-100). */
	public function new(period:Int, ?factor:Float) {
		if (period <= 0) throw "Cci: period must be > 0";
		var f = factor != null ? factor : 0.015;
		if (!Math.isFinite(f) || f <= 0) throw "Cci: factor must be positive and finite";
		this.period = period;
		this.factor = f;
		window = [];
		sum = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var tp = (bar.high + bar.low + bar.close) / 3.0;
		if (window.length == period) sum -= window.shift();
		window.push(tp);
		sum += tp;
		if (window.length < period) return null;
		var n:Float = period;
		var mean = sum / n;
		var mad = 0.0;
		for (v in window) mad += Math.abs(v - mean);
		mad /= n;
		if (mad == 0) return 0.0;
		return (tp - mean) / (factor * mad);
	}

	public function reset():Void {
		window = [];
		sum = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "CCI";
}
