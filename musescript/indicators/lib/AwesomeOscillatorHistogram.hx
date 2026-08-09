package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Awesome Oscillator Histogram — ported from wickra-core's `AwesomeOscillatorHistogram`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/awesome_oscillator_histogram.rs).
 *
 * The bar-to-bar **momentum** of the Awesome Oscillator over a `lookback` window.
 * This is the value behind the coloured histogram bars in Bill Williams' charts:
 * each bar shows how much `AO` has changed, so positive values mean `AO` is
 * rising (the histogram "greens up") and negative values mean it is falling.
 *
 * ```text
 * AO     = SMA(median, fast) − SMA(median, slow)
 * AOHist = AO_t − AO_{t−lookback}
 * ```
 *
 * This reports `AO`'s rate of change. The default `lookback` is `1`
 * (the classic one-bar histogram delta).
 */
class AwesomeOscillatorHistogram implements MuseIndicator<Bar, Float> {
	var fastPeriod:Int;
	var slowPeriod:Int;
	var lookback:Int;
	var ao:AwesomeOscillator;
	var history:RingBuffer<Float>;
	var emitted:Bool;

	public function new(fast:Int, slow:Int, lookback:Int) {
		if (fast <= 0 || slow <= 0 || lookback <= 0) {
			throw "AwesomeOscillatorHistogram: all periods must be > 0";
		}
		if (fast >= slow) {
			throw "AwesomeOscillatorHistogram: fast must be strictly less than slow";
		}
		this.fastPeriod = fast;
		this.slowPeriod = slow;
		this.lookback = lookback;
		this.ao = new AwesomeOscillator(fast, slow);
		reset();
	}

	/** Bill Williams' defaults with a one-bar histogram delta `(5, 34, 1)`. */
	public static function classic():AwesomeOscillatorHistogram {
		return new AwesomeOscillatorHistogram(5, 34, 1);
	}

	public function update(bar:Bar):Null<Float> {
		var ao = this.ao.update(bar);
		if (ao == null) return null;
		history.push(ao);
		if (history.length <= lookback) return null;
		// Capacity is lookback+1: oldest is AO_{t−lookback}.
		var prev = history.oldest(0);
		emitted = true;
		return ao - prev;
	}

	public function reset():Void {
		ao.reset();
		history = new RingBuffer(lookback + 1);
		emitted = false;
	}

	public function warmupPeriod():Int {
		// AO first emits at `slow` candles; `lookback` more AO values are then
		// needed before `AO_t − AO_{t−lookback}` can be formed.
		return slowPeriod + lookback;
	}

	public function isReady():Bool return emitted;
	public function name():String return "AwesomeOscillatorHistogram";

	public static function spec():IndicatorSpec {
		return {
			name: "awesome_oscillator_histogram", args: [TWindow, TWindow, TWindow], ret: TScalar, minArgs: 3,
			eval: function(h, args) {
				var f = IndicatorCache.intArg(args, 0, 5);
				var s = IndicatorCache.intArg(args, 1, 34);
				var l = IndicatorCache.intArg(args, 2, 1);
				return IndicatorCache.evalBar(h, "awesome_oscillator_histogram:" + f + ":" + s + ":" + l, Math.NaN,
					() -> new AwesomeOscillatorHistogram(f, s, l),
					(i, b) -> (cast i : AwesomeOscillatorHistogram).update(b));
			}
		};
	}
}
