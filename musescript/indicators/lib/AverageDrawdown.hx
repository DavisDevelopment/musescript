package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Rolling Average Drawdown — ported from wickra-core's `AverageDrawdown`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/average_drawdown.rs).
 *
 * Input is treated as an equity-curve sample. Over the trailing window of
 * `period` values the indicator identifies each **distinct drawdown episode**
 * — a stretch where equity is below the running peak — and reports the **mean
 * of the episodes' maximum depths**:
 *
 * ```text
 * episode opens when equity < running peak
 * episode closes when equity reaches a new peak (full recovery)
 * depth(episode) = (episode_peak − episode_trough) / episode_peak
 * AvgDD          = mean(depth over episodes in window)   (0 if no drawdown)
 * ```
 *
 * Output is a non-negative fraction (`0.05` ≈ 5% mean episode depth).
 * Each `update` is O(period).
 */
class AverageDrawdown implements MuseIndicator<Float, Float> {
	var period:Int;
	var window:RingBuffer<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "AverageDrawdown: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return null;
		window.push(input);
		if (window.length < period) return null;

		var peak = Math.NEGATIVE_INFINITY;
		var sumDepth = 0.0;
		var episodes:Int = 0;
		var inDd = false;
		var episodePeak = 0.0;
		var episodeTrough = 0.0;

		for (v in window) {
			if (v >= peak) {
				if (inDd) {
					if (episodePeak > 0.0) {
						sumDepth += (episodePeak - episodeTrough) / episodePeak;
						episodes++;
					}
					inDd = false;
				}
				peak = v;
			} else if (inDd) {
				if (v < episodeTrough) {
					episodeTrough = v;
				}
			} else {
				inDd = true;
				episodePeak = peak;
				episodeTrough = v;
			}
		}

		if (inDd && episodePeak > 0.0) {
			sumDepth += (episodePeak - episodeTrough) / episodePeak;
			episodes++;
		}

		return if (episodes == 0) 0.0 else sumDepth / episodes;
	}

	public function reset():Void {
		window = new RingBuffer(period);
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return window.length == period;
	public function name():String return "AverageDrawdown";

	public static function spec():IndicatorSpec {
		return {
			name: "average_drawdown", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 10);
				return IndicatorCache.evalSeries(h, "average_drawdown:" + p, "close", Math.NaN,
					() -> new AverageDrawdown(p), (i, v) -> (cast i : AverageDrawdown).update(v));
			}
		};
	}
}
