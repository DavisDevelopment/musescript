package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Shooting Star candlestick pattern — a single-bar bearish reversal
 * candidate. Same geometry as an Inverted Hammer (small body near the
 * bottom, long upper shadow >= 2x body, short lower shadow) but read
 * bearishly.
 *
 * body         = |close - open|
 * upper_shadow = high - max(open, close)
 * lower_shadow = min(open, close) - low
 * star         = upper_shadow >= 2 * body
 *                && lower_shadow <= body
 *                && body > 0
 *
 * Output is -1.0 when the shape matches, 0.0 otherwise — bearish by
 * definition, it never emits +1.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/shooting_star.rs
 */
class ShootingStar implements MuseIndicator<Bar, Float> {
	var hasEmitted:Bool;

	public function new() {
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var range = candle.high - candle.low;
		if (range <= 0.0) return 0.0;
		var body = Math.abs(candle.close - candle.open);
		if (body <= 0.0) return 0.0;
		var upper = candle.high - Math.max(candle.open, candle.close);
		var lower = Math.min(candle.open, candle.close) - candle.low;
		return (upper >= 2.0 * body && lower <= body) ? -1.0 : 0.0;
	}

	public function reset():Void {
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return hasEmitted;
	public function name():String return "ShootingStar";

	public static function spec():IndicatorSpec {
		return {
			name: "shooting_star", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "shooting_star", Math.NaN,
				() -> new ShootingStar(), (i, b) -> (cast i : ShootingStar).update(b))
		};
	}
}
