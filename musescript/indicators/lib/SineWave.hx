package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.HilbertDominantCycle;
import musescript.types.MuseType;

/**
 * Ehlers' Sine Wave indicator (sine + leadsine) — ported from wickra-core's
 * `SineWave`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/sine_wave.rs).
 *
 * From *Rocket Science for Traders* (Ehlers 2001, ch. 9). Uses the same
 * Hilbert-transform machinery as `HilbertDominantCycle` to derive the
 * instantaneous phase, then returns `sin(phase)`; the 45°-lead
 * `sin(phase + 45°)` is available via the `lead()` accessor. Series input
 * (f64): `sine_wave(close)`.
 */
class SineWave implements MuseIndicator<Float, Float> {
	static inline var EPSILON:Float = 2.220446049250313e-16;

	var cycle:HilbertDominantCycle;
	var smoothBuf:Array<Float>;
	var detrenderBuf:Array<Float>;
	var lastPhase:Float;
	var lastSine:Null<Float>;
	var lastLead:Float;
	var count:Int;

	public function new() {
		cycle = new HilbertDominantCycle();
		smoothBuf = [];
		detrenderBuf = [];
		lastPhase = 0.0;
		lastSine = null;
		lastLead = 0.0;
		count = 0;
	}

	/** Most recent lead (45°-ahead) value. `0.0` until the indicator is ready. */
	public function lead():Float return lastLead;

	/** Current sine value if available. */
	public function value():Null<Float> return lastSine;

	static function pushFront(buf:Array<Float>, v:Float, cap:Int):Void {
		buf.unshift(v);
		if (buf.length > cap) {
			buf.splice(cap, buf.length - cap);
		}
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return lastSine;
		count++;
		// Drive the dominant-cycle estimator first; its smoothing state is
		// independent from ours so the two share input but not buffers.
		var cycleVal = cycle.update(input);

		pushFront(smoothBuf, input, 7);
		if (smoothBuf.length < 4) return null;
		var smooth = (4.0 * smoothBuf[0] + 3.0 * smoothBuf[1] + 2.0 * smoothBuf[2] + smoothBuf[3]) / 10.0;
		if (smoothBuf.length < 7) return null;

		var period = cycleVal != null ? cycleVal : 15.0;
		period = Math.min(Math.max(period, 6.0), 50.0);
		var adj = 0.075 * period + 0.54;
		var s0 = smooth;
		var s2 = smoothBuf[2];
		var s4 = smoothBuf[4];
		var s6 = smoothBuf[6];
		var detrender = (0.0962 * s0 + 0.5769 * s2 - 0.5769 * s4 - 0.0962 * s6) * adj;
		pushFront(detrenderBuf, detrender, 7);
		if (detrenderBuf.length < 7) return null;

		var q1 = (0.0962 * detrenderBuf[0] + 0.5769 * detrenderBuf[2]
			- 0.5769 * detrenderBuf[4] - 0.0962 * detrenderBuf[6]) * adj;
		var i1 = detrenderBuf[3];
		var phase = if (Math.abs(i1) > EPSILON) {
			Math.atan(q1 / i1);
		} else {
			lastPhase;
		};
		lastPhase = phase;
		var sine = Math.sin(phase);
		var leadVal = Math.sin(phase + Math.PI / 4.0);

		if (count < 50) return null;
		lastSine = sine;
		lastLead = leadVal;
		return sine;
	}

	public function reset():Void {
		cycle.reset();
		smoothBuf = [];
		detrenderBuf = [];
		lastPhase = 0.0;
		lastSine = null;
		lastLead = 0.0;
		count = 0;
	}

	public function warmupPeriod():Int return 50;
	public function isReady():Bool return lastSine != null;
	public function name():String return "SineWave";

	public static function spec():IndicatorSpec {
		return {
			name: "sine_wave", args: [TSeries], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				return IndicatorCache.evalSeries(h, "sine_wave:" + series, series, Math.NaN,
					() -> new SineWave(), (i, v) -> (cast i : SineWave).update(v));
			}
		};
	}
}
