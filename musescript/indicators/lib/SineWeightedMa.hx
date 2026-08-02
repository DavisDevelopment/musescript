package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Sine-Weighted Moving Average (SWMA) — ported from wickra-core's
 * `SineWeightedMa`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/sine_weighted_ma.rs).
 *
 * Over the last `period` inputs the weight of the value at position
 * `i = 0..period-1` (oldest to newest) is `sin(π·(i+1)/(period+1))`;
 * `SWMA = Σ(w_i·value_i) / Σ w_i`. Weights rise to a peak mid-window and
 * fall off at both ends. `period == 1` collapses to a pass-through.
 * Series input (f64): `sine_weighted_ma(close, period)`.
 */
class SineWeightedMa implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;
	/** Sine weights for positions `0..period` (oldest to newest), constant in `period`. */
	var weights:Array<Float>;
	var weightsTotal:Float;

	public function new(period:Int) {
		if (period <= 0) throw "SineWeightedMa: period must be > 0";
		this.period = period;
		var denom = period + 1.0;
		weights = [for (i in 0...period) Math.sin(Math.PI * (i + 1.0) / denom)];
		weightsTotal = 0.0;
		for (w in weights) weightsTotal += w;
		window = new RingBuffer(period);
	}

	/** Configured period. */
	public function getPeriod():Int return period;

	/** Current value if the window is full. */
	public function value():Null<Float> {
		if (window.length == period) {
			var dot = 0.0;
			for (i in 0...period) dot += window.oldest(i) * weights[i];
			return dot / weightsTotal;
		}
		return null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return value();
		window.push(input);
		return value();
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "SWMA";

	public static function spec():IndicatorSpec {
		return {
			name: "sine_weighted_ma", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "sine_weighted_ma:" + series + ":" + p, series, Math.NaN,
					() -> new SineWeightedMa(p), (i, v) -> (cast i : SineWeightedMa).update(v));
			}
		};
	}
}
