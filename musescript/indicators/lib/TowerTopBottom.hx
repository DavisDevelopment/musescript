package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tower Top / Tower Bottom — ported from wickra-core's `TowerTopBottom`
 * (vendor/wickra/crates/wickra-core/src/indicators/tower_top_bottom.rs).
 *
 * A reversal where a strong directional bar is followed by a small "pause"
 * bar and then a strong bar in the OPPOSITE direction, like two towers
 * flanking a low wall (compact three-bar form of the classic Tower pattern):
 *
 *   Tower Bottom (+1.0): tall bearish bar, small-bodied bar, tall bullish bar.
 *   Tower Top    (-1.0): tall bullish bar, small-bodied bar, tall bearish bar.
 *   Otherwise 0.0.
 *
 * "Tall" = body >= 0.5 * range; "small" = body <= 0.3 * range. The three-bar
 * lookback means the first value lands on the third candle (the first two
 * bars seed and emit 0.0).
 */
class TowerTopBottom implements MuseIndicator<Bar, Float> {
	var c1:Null<Bar>;
	var c2:Null<Bar>;
	var lastValue:Null<Float>;

	public function new() {
		c1 = null;
		c2 = null;
		lastValue = null;
	}

	static function bodyFraction(candle:Bar):Float {
		var range = candle.high - candle.low;
		return range > 0.0 ? Math.abs(candle.close - candle.open) / range : 0.0;
	}

	static function isTall(candle:Bar):Bool {
		return bodyFraction(candle) >= 0.5;
	}

	static function isSmall(candle:Bar):Bool {
		return bodyFraction(candle) <= 0.3;
	}

	/** Latest emitted signal if available. */
	public function value():Null<Float> {
		return lastValue;
	}

	public function update(candle:Bar):Null<Float> {
		if (c1 == null || c2 == null) {
			c1 = c2;
			c2 = candle;
			lastValue = 0.0;
			return 0.0;
		}
		var first = c1;
		var middle = c2;
		var pause = isSmall(middle);
		var firstTall = isTall(first);
		var lastTall = isTall(candle);
		var v = if (pause && firstTall && lastTall) {
			var firstUp = first.close > first.open;
			var lastUp = candle.close > candle.open;
			if (!firstUp && lastUp) {
				1.0;
			} else if (firstUp && !lastUp) {
				-1.0;
			} else {
				0.0;
			}
		} else {
			0.0;
		}
		c1 = c2;
		c2 = candle;
		lastValue = v;
		return v;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		lastValue = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return lastValue != null;
	public function name():String return "TowerTopBottom";

	public static function spec():IndicatorSpec {
		return {
			name: "tower_top_bottom", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "tower_top_bottom", Math.NaN,
				() -> new TowerTopBottom(), (i, b) -> (cast i : TowerTopBottom).update(b))
		};
	}
}
