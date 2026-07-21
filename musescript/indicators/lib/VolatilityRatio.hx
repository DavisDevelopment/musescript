package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Schwager's Volatility Ratio — ported from wickra-core's `VolatilityRatio`
 * (vendor/wickra/crates/wickra-core/src/indicators/volatility_ratio.rs).
 *
 *   TR_t = true range of bar t
 *   VR_t = TR_t / EMA_n(TR through bar t−1)
 *
 * The denominator is a *standard* EMA (alpha = 2 / (period + 1)) of true
 * range excluding the current bar, seeded with the simple average of the
 * first `period` true ranges — a single large bar stands out instead of
 * inflating its own benchmark. A reading above 2.0 marks a wide-ranging day.
 * A flat benchmark yields 0.0, not 0/0. First value after `period + 2` bars.
 */
class VolatilityRatio implements MuseIndicator<Bar, Float> {
	var period:Int;
	var alpha:Float;
	var prevClose:Null<Float>;
	/** Sum and count of the first `period` true ranges, used to seed the EMA. */
	var seedSum:Float;
	var seedCount:Int;
	/** EMA of true range through the previous bar; null until seeded. */
	var ema:Null<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "VolatilityRatio: period must be > 0";
		this.period = period;
		alpha = 2.0 / (period + 1.0);
		reset();
	}

	public function update(candle:Bar):Null<Float> {
		// The first bar has no previous close, so no true range can be formed.
		if (prevClose == null) {
			prevClose = candle.close;
			return null;
		}
		var pc:Float = prevClose;
		var hl = candle.high - candle.low;
		var hc = Math.abs(candle.high - pc);
		var lc = Math.abs(candle.low - pc);
		var tr = Math.max(hl, Math.max(hc, lc));
		prevClose = candle.close;

		if (ema == null) {
			// Seeding the EMA with the simple average of the first `period`
			// true ranges; emit nothing until it is established.
			seedSum += tr;
			seedCount++;
			if (seedCount == period) ema = seedSum / period;
			return null;
		}
		var prevEma:Float = ema;
		// Denominator excludes the current bar (it is the EMA through the
		// previous bar). A flat benchmark yields 0.0, not 0/0.
		var vr = prevEma > 0.0 ? tr / prevEma : 0.0;
		ema = alpha * tr + (1.0 - alpha) * prevEma;
		last = vr;
		return vr;
	}

	public function reset():Void {
		prevClose = null;
		seedSum = 0.0;
		seedCount = 0;
		ema = null;
		last = null;
	}

	public function warmupPeriod():Int return period + 2;
	public function isReady():Bool return last != null;
	public function name():String return "VolatilityRatio";

	public static function spec():IndicatorSpec {
		return {
			name: "volatility_ratio", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "volatility_ratio:" + p, Math.NaN,
					() -> new VolatilityRatio(p), (i, b) -> (cast i : VolatilityRatio).update(b));
			}
		};
	}
}
