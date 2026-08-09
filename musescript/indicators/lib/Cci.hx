package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

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
	var window:RingBuffer<Float>;
	var sum:Float;

	/** `factor` defaults to the canonical 0.015 (puts ~70% of values inside +/-100). */
	public function new(period:Int, ?factor:Float) {
		if (period <= 0) throw "Cci: period must be > 0";
		var f = factor != null ? factor : 0.015;
		if (!Math.isFinite(f) || f <= 0) throw "Cci: factor must be positive and finite";
		this.period = period;
		this.factor = f;
		window = new RingBuffer(period);
		sum = 0.0;
	}

	public function update(bar:Bar):Null<Float> {
		var tp = (bar.high + bar.low + bar.close) / 3.0;
		// Fullness checked before push — `Null<Float>` of `0.0` is nullish on JS.
		var wasFull = window.isFull();
		var old = window.push(tp);
		if (wasFull) sum -= old;
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
		window = new RingBuffer(period);
		sum = 0.0;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "CCI";

	public static function spec():IndicatorSpec {
		return {
			name: "cci", args: [TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var f = args.length > 1 && args[1] != null ? IndicatorCache.floatArg(args, 1, 0.015) : 0.015;
				return IndicatorCache.evalBar(h, "cci:" + p + ":" + f, Math.NaN,
					() -> new Cci(p, f), (i, b) -> (cast i : Cci).update(b));
			}
		};
	}
}
