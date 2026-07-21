package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Three White Soldiers / Three Black Crows candlestick pattern — a 3-bar
 * continuation pattern of three consecutive long candles in the same
 * direction, each opening inside the previous body and closing beyond it.
 *
 * Three White Soldiers (+1.0):
 *   all three green & monotonically rising closes
 *     & each open in [prev.open, prev.close]
 *     & each close > prev.close
 *
 * Three Black Crows (-1.0): the mirror — three red candles with
 * monotonically falling closes.
 *
 * Output is 0.0 otherwise; the first two bars always return 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/three_soldiers_or_crows.rs
 */
class ThreeSoldiersOrCrows implements MuseIndicator<Bar, Float> {
	var prev:Null<Bar>;
	var prevPrev:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var b1 = prevPrev;
		var b2 = prev;
		prevPrev = prev;
		prev = candle;
		if (b1 == null || b2 == null) return 0.0;
		var g1 = b1.close > b1.open;
		var g2 = b2.close > b2.open;
		var g3 = candle.close > candle.open;
		var r1 = b1.close < b1.open;
		var r2 = b2.close < b2.open;
		var r3 = candle.close < candle.open;
		// Three White Soldiers
		if (g1
			&& g2
			&& g3
			&& b2.close > b1.close
			&& candle.close > b2.close
			&& b2.open >= b1.open
			&& b2.open <= b1.close
			&& candle.open >= b2.open
			&& candle.open <= b2.close) {
			return 1.0;
		}
		// Three Black Crows
		if (r1
			&& r2
			&& r3
			&& b2.close < b1.close
			&& candle.close < b2.close
			&& b2.open <= b1.open
			&& b2.open >= b1.close
			&& candle.open <= b2.open
			&& candle.open >= b2.close) {
			return -1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		prevPrev = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return hasEmitted;
	public function name():String return "ThreeSoldiersOrCrows";

	public static function spec():IndicatorSpec {
		return {
			name: "three_soldiers_or_crows", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "three_soldiers_or_crows", Math.NaN,
				() -> new ThreeSoldiersOrCrows(), (i, b) -> (cast i : ThreeSoldiersOrCrows).update(b))
		};
	}
}
