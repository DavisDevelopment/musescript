package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.SuperSmoother;
import musescript.types.MuseType;

/**
 * Ehlers Empirical Mode Decomposition (EMD) — ported from wickra-core's `EmpiricalModeDecomposition`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/empirical_mode_decomposition.rs).
 *
 * Implementation per *Cycle Analytics for Traders* (Ehlers 2013, ch. 14).
 * Applies a bandpass filter centred on `period`, detects peaks/valleys within a
 * `fraction` window, averages them separately to form upper/lower envelopes,
 * and returns the centred bandpass minus the envelope mean.
 *
 * The output crosses zero at trend changes and stays near zero in non-trending
 * markets — the classic visual cue Ehlers documents.
 */
class EmpiricalModeDecomposition implements MuseIndicator<Float, Float> {
	var period:Int;
	var fraction:Float;
	var bandpass:Float;
	var prevBp1:Float;
	var prevBp2:Float;
	var prevIn1:Null<Float>;
	var prevIn2:Null<Float>;
	var beta:Float;
	var alpha:Float;
	var smoother:SuperSmoother;
	var peakSmoother:SuperSmoother;
	var valleySmoother:SuperSmoother;
	var bpBuf:Array<Float>;
	var bpHistoryLen:Int;
	var lastValue:Null<Float>;

	public function new(period:Int, fraction:Float) {
		if (period <= 0) throw "EmpiricalModeDecomposition: period must be > 0";
		if (!Math.isFinite(fraction) || fraction <= 0.0 || fraction > 1.0) {
			throw "EmpiricalModeDecomposition: fraction must be in (0, 1]";
		}

		this.period = period;
		this.fraction = fraction;
		this.bandpass = 0.0;
		this.prevBp1 = 0.0;
		this.prevBp2 = 0.0;
		this.prevIn1 = null;
		this.prevIn2 = null;

		var pi = Math.PI;
		this.beta = Math.cos(2.0 * pi / period);
		var gamma = 1.0 / Math.cos(2.0 * pi * 0.25 / period);
		this.alpha = gamma - Math.sqrt(gamma * gamma - 1.0);

		var minPeriod = period < 2 ? 2 : period;
		this.smoother = new SuperSmoother(minPeriod);
		this.peakSmoother = new SuperSmoother(minPeriod);
		this.valleySmoother = new SuperSmoother(minPeriod);

		// Rust: `(period as f64 * fraction).round().max(1.0)` -- round, not ceil.
		this.bpHistoryLen = Math.round(period * fraction);
		if (bpHistoryLen < 1) bpHistoryLen = 1;

		this.bpBuf = [];
		this.lastValue = null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			return lastValue;
		}

		// 2nd-order resonant bandpass per Ehlers ch. 6.
		var bp:Float = if (prevIn1 != null && prevIn2 != null) {
			0.5 * (1.0 - alpha) * (input - prevIn2)
				+ beta * (1.0 + alpha) * prevBp1
				- alpha * prevBp2;
		} else {
			0.0;
		};

		prevBp2 = prevBp1;
		prevBp1 = bp;
		bandpass = bp;
		prevIn2 = prevIn1;
		prevIn1 = input;

		if (bpBuf.length == bpHistoryLen) {
			bpBuf.shift();
		}
		bpBuf.push(bp);

		if (bpBuf.length < bpHistoryLen) {
			return null;
		}

		// Find peak (max) and valley (min) in the buffer.
		var peak = bpBuf[0], valley = bpBuf[0];
		for (i in 1...bpBuf.length) {
			if (bpBuf[i] >= peak) peak = bpBuf[i];
			if (bpBuf[i] <= valley) valley = bpBuf[i];
		}

		var avgPeak = peakSmoother.update(peak);
		var avgValley = valleySmoother.update(valley);

		if (avgPeak == null || avgValley == null) {
			return null;
		}

		// The EMD line is the bandpass minus the smoothed mean envelope.
		var mean = 0.5 * (avgPeak + avgValley);
		var raw = bp - mean;
		var v = smoother.update(raw);
		if (v == null) return null;

		lastValue = v;
		return v;
	}

	public function reset():Void {
		bandpass = 0.0;
		prevBp1 = 0.0;
		prevBp2 = 0.0;
		prevIn1 = null;
		prevIn2 = null;
		smoother.reset();
		peakSmoother.reset();
		valleySmoother.reset();
		bpBuf = [];
		lastValue = null;
	}

	public function warmupPeriod():Int return bpHistoryLen;
	public function isReady():Bool return lastValue != null;
	public function name():String return "EmpiricalModeDecomposition";

	public static function spec():IndicatorSpec {
		return {
			name: "empirical_mode_decomposition", args: [TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				var f = IndicatorCache.floatArg(args, 1, 0.5);
				return IndicatorCache.evalSeries(h, "empirical_mode_decomposition:" + p + ":" + f, "close", Math.NaN,
					() -> new EmpiricalModeDecomposition(p, f),
					(i, v) -> (cast i : EmpiricalModeDecomposition).update(v));
			}
		};
	}
}
