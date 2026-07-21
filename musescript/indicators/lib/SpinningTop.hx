package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Spinning Top candlestick pattern — a single-bar indecision candle with a
 * small body and two long shadows.
 *
 * body         = |close - open|
 * upper_shadow = high - max(open, close)
 * lower_shadow = min(open, close) - low
 * range        = high - low
 * spinning     = body <= body_threshold * range
 *                && upper_shadow >= 2 * body
 *                && lower_shadow >= 2 * body
 *                && body > 0
 *
 * While direction is ambiguous by intent, the output is direction-signed so
 * downstream filters can distinguish a green spinning top (+1.0) from a red
 * one (-1.0). A clean Doji (body == 0) is *not* a Spinning Top.
 *
 * `bodyThreshold` defaults to 0.3 and must lie in (0, 1].
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/spinning_top.rs
 */
class SpinningTop implements MuseIndicator<Bar, Float> {
	var _bodyThreshold:Float;
	var hasEmitted:Bool;

	public function new(bodyThreshold:Float = 0.3) {
		if (!(bodyThreshold > 0.0 && bodyThreshold <= 1.0)) throw "spinning top body threshold must lie in (0, 1]";
		this._bodyThreshold = bodyThreshold;
		hasEmitted = false;
	}

	/** Configured body / range threshold. */
	public function bodyThreshold():Float return _bodyThreshold;

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var range = candle.high - candle.low;
		if (range <= 0.0) return 0.0;
		var bodySigned = candle.close - candle.open;
		var body = Math.abs(bodySigned);
		if (body <= 0.0) return 0.0;
		if (body > _bodyThreshold * range) return 0.0;
		var upper = candle.high - Math.max(candle.open, candle.close);
		var lower = Math.min(candle.open, candle.close) - candle.low;
		if (upper >= 2.0 * body && lower >= 2.0 * body) {
			return bodySigned > 0.0 ? 1.0 : -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "SpinningTop";

	public static function spec():IndicatorSpec {
		return {
			name: "spinning_top", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var t = args.length > 0 ? IndicatorCache.floatArg(args, 0, 0.3) : 0.3;
				return IndicatorCache.evalBar(h, "spinning_top:" + t, Math.NaN,
					() -> new SpinningTop(t), (i, b) -> (cast i : SpinningTop).update(b));
			}
		};
	}
}
