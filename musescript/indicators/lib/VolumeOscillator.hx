package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Volume Oscillator — ported from wickra-core's `VolumeOscillator`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/volume_oscillator.rs).
 *
 * The percent difference between a fast and a slow SMA of the bar volume:
 *
 *   VO_t = 100 * (SMA(volume, fast)_t - SMA(volume, slow)_t) / SMA(volume, slow)_t
 *
 * A slow average of 0 (whole slow window zero-volume) collapses the output
 * to 0 rather than NaN. Classic configuration is fast = 14, slow = 28.
 */
class VolumeOscillator implements MuseIndicator<Bar, Float> {
	var fastPeriod:Int;
	var slowPeriod:Int;
	var fast:Sma;
	var slow:Sma;

	public function new(fast:Int, slow:Int) {
		if (fast <= 0 || slow <= 0) throw "VolumeOscillator: periods must be > 0";
		if (fast >= slow) throw "VolumeOscillator needs fast < slow";
		this.fastPeriod = fast;
		this.slowPeriod = slow;
		this.fast = new Sma(fast);
		this.slow = new Sma(slow);
	}

	public function update(bar:Bar):Null<Float> {
		var f = fast.update(bar.volume);
		var s = slow.update(bar.volume);
		if (f == null || s == null) return null;
		if (s == 0.0) {
			// Whole slow window is zero-volume — the ratio is undefined; report 0.
			return 0.0;
		}
		return 100.0 * (f - s) / s;
	}

	public function reset():Void {
		fast.reset();
		slow.reset();
	}

	public function warmupPeriod():Int return slowPeriod;
	public function isReady():Bool return slow.isReady();
	public function name():String return "VolumeOscillator";

	/** Configured (fast, slow) periods. */
	public function periods():{fast:Int, slow:Int} return {fast: fastPeriod, slow: slowPeriod};

	public static function spec():IndicatorSpec {
		return {
			name: "volume_oscillator", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var fast = IndicatorCache.intArg(args, 0, 14);
				var slow = IndicatorCache.intArg(args, 1, 28);
				return IndicatorCache.evalBar(h, "volume_oscillator:" + fast + ":" + slow, Math.NaN,
					() -> new VolumeOscillator(fast, slow), (i, b) -> (cast i : VolumeOscillator).update(b));
			}
		};
	}
}
