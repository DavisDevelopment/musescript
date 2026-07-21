package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** ZigZag output: the just-completed swing extreme and its direction (+1 high / -1 low). */
typedef ZigZagOutput = {
	var swing:Float;
	var direction:Float;
}

/**
 * ZigZag — ported from wickra-core's `ZigZag`
 * (vendor/wickra/crates/wickra-core/src/indicators/zig_zag.rs).
 *
 * A non-repainting percent-threshold swing detector. Tracks the most recent
 * extreme (high or low) and confirms a reversal once price has moved the
 * configured percentage away from it.
 *
 * Emits a value only on the bar where a reversal is confirmed, returning the
 * price and direction of the JUST-COMPLETED extreme; bars between
 * confirmations return null. The first bar bootstraps the state without
 * emitting. The threshold is a fractional change (0.05 ≈ 5%); it must be
 * finite and strictly inside (0, 1).
 */
class ZigZag implements MuseIndicator<Bar, ZigZagOutput> {
	var thresholdValue:Float;
	var state:Null<ZigZagState>;

	public function new(threshold:Float) {
		if (!Math.isFinite(threshold) || threshold <= 0.0 || threshold >= 1.0)
			throw "ZigZag threshold must be a finite fraction in (0, 1)";
		this.thresholdValue = threshold;
		state = null;
	}

	/** Configured reversal threshold (fractional). */
	public function threshold():Float {
		return thresholdValue;
	}

	public function update(candle:Bar):Null<ZigZagOutput> {
		if (state == null) {
			// Bootstrap: seed an uptrend tracking the first candle's high.
			state = {direction: 1.0, extreme: candle.high};
			return null;
		}

		var s = state;
		if (s.direction > 0.0) {
			// Uptrend: keep raising the candidate high; confirm reversal if
			// the candle's low has dropped by threshold from the candidate.
			if (candle.high > s.extreme) {
				state = {direction: 1.0, extreme: candle.high};
				return null;
			}
			if (candle.low <= s.extreme * (1.0 - thresholdValue)) {
				// Confirm the swing high; flip to downtrend tracking this bar's low.
				var confirmed:ZigZagOutput = {swing: s.extreme, direction: 1.0};
				state = {direction: -1.0, extreme: candle.low};
				return confirmed;
			}
			return null;
		} else {
			// Downtrend: lower the candidate low; confirm reversal if the
			// candle's high has risen by threshold from the candidate.
			if (candle.low < s.extreme) {
				state = {direction: -1.0, extreme: candle.low};
				return null;
			}
			if (candle.high >= s.extreme * (1.0 + thresholdValue)) {
				var confirmed:ZigZagOutput = {swing: s.extreme, direction: -1.0};
				state = {direction: 1.0, extreme: candle.high};
				return confirmed;
			}
			return null;
		}
	}

	public function reset():Void {
		state = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return state != null;
	public function name():String return "ZigZag";

	public static function spec():IndicatorSpec {
		return {
			name: "zig_zag", args: [TScalar], ret: TObject([
				{name: "swing", ty: TScalar},
				{name: "direction", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var t = IndicatorCache.floatArg(args, 0, 0.05);
				var nanFill:ZigZagOutput = {swing: Math.NaN, direction: Math.NaN};
				return IndicatorCache.evalBar(h, "zig_zag:" + t, nanFill,
					() -> new ZigZag(t), (i, b) -> (cast i : ZigZag).update(b));
			}
		};
	}
}

private typedef ZigZagState = {
	var direction:Float;
	var extreme:Float;
}
