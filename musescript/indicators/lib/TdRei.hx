package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.RingBuffer;
import musescript.types.MuseType;

/**
 * Tom DeMark Range Expansion Index (TD REI) — ported from wickra-core's `TdRei`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_rei.rs).
 *
 * A `period`-bar bounded oscillator in [-100, 100]. Per bar i (history
 * through i-6 required):
 *   cond1 = high[i] >= low[i-5] OR high[i] >= low[i-6]
 *   cond2 = low[i] <= high[i-5] OR low[i] <= high[i-6]
 *   numerator   = cond1 && cond2 ? (high[i]-high[i-2]) + (low[i]-low[i-2]) : 0
 *   denominator = |high[i]-high[i-2]| + |low[i]-low[i-2]|
 *   REI = 100 * sum(numerator, period) / sum(denominator, period)
 * A zero windowed denominator falls back to the neutral 0.
 */
class TdRei implements MuseIndicator<Bar, Float> {
	/** Minimum history for the per-bar rule (references bar[i-6]). */
	static inline var LOOKBACK = 7;

	var period:Int;
	var candles:RingBuffer<Bar>;
	var numerators:RingBuffer<Float>;
	var denominators:RingBuffer<Float>;
	var lastValue:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "TdRei: period must be > 0";
		this.period = period;
		reset();
	}

	/** DeMark's classic configuration: period = 5. */
	public static function classic():TdRei return new TdRei(5);

	/** Configured window. */
	public function getPeriod():Int return period;

	/** Latest emitted value if available. */
	public function value():Null<Float> return lastValue;

	public function update(bar:Bar):Null<Float> {
		// Need 6 previous candles before evaluating the rule.
		if (candles.length < LOOKBACK - 1) {
			candles.push(bar);
			return null;
		}
		// Eviction-before-read: when full (LOOKBACK), prior-6 slice starts at oldest(1).
		var base = candles.length - (LOOKBACK - 1);
		var prev2 = candles.oldest(base + (LOOKBACK - 1) - 2);
		var prev5 = candles.oldest(base + 1);
		var prev6 = candles.oldest(base + 0);

		var cond1 = bar.high >= prev5.low || bar.high >= prev6.low;
		var cond2 = bar.low <= prev5.high || bar.low <= prev6.high;

		var rawNum = (bar.high - prev2.high) + (bar.low - prev2.low);
		var denominator = Math.abs(bar.high - prev2.high) + Math.abs(bar.low - prev2.low);
		var numerator = cond1 && cond2 ? rawNum : 0.0;

		numerators.push(numerator);
		denominators.push(denominator);
		candles.push(bar);

		if (numerators.length < period) return null;
		var sumNum = 0.0, sumDen = 0.0;
		for (i in 0...numerators.length) sumNum += numerators.oldest(i);
		for (i in 0...denominators.length) sumDen += denominators.oldest(i);
		var v = sumDen == 0.0 ? 0.0 : 100.0 * sumNum / sumDen;
		lastValue = v;
		return v;
	}

	public function reset():Void {
		candles = new RingBuffer(LOOKBACK);
		numerators = new RingBuffer(period);
		denominators = new RingBuffer(period);
		lastValue = null;
	}

	/** 6 bars to fill the lookback plus `period` updates to fill the buffers. */
	public function warmupPeriod():Int return (LOOKBACK - 1) + period;

	public function isReady():Bool return lastValue != null;
	public function name():String return "TDREI";

	public static function spec():IndicatorSpec {
		return {
			name: "td_rei", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 5);
				return IndicatorCache.evalBar(h, "td_rei:" + p, Math.NaN,
					() -> new TdRei(p), (i, b) -> (cast i : TdRei).update(b));
			}
		};
	}
}
