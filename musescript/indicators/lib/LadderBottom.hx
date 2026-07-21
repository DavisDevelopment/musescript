package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Ladder Bottom candlestick pattern — a 5-bar bullish reversal. Three long
 * black candles step the market down like rungs of a ladder, a fourth black
 * candle finally shows an upper shadow (the first sign of buying), and a
 * white candle then gaps up into its body to confirm the turn.
 *
 * bar1, bar2, bar3 black, with consecutively lower opens AND closes
 * bar4 black with an upper shadow          (high4 > open4)
 * bar5 white, opens above bar4's open      (open5 > open4) and closes up
 *
 * Output is +1.0 when the pattern completes and 0.0 otherwise (bullish-only,
 * never emits -1.0). The first four bars always return 0.0.
 *
 * Ported from vendor/wickra/crates/wickra-core/src/indicators/ladder_bottom.rs
 */
class LadderBottom implements MuseIndicator<Bar, Float> {
	var c1:Null<Bar>;
	var c2:Null<Bar>;
	var c3:Null<Bar>;
	var c4:Null<Bar>;
	var hasEmitted:Bool;

	public function new() {
		c1 = null;
		c2 = null;
		c3 = null;
		c4 = null;
		hasEmitted = false;
	}

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var bar1 = c1;
		var bar2 = c2;
		var bar3 = c3;
		var bar4 = c4;
		c1 = c2;
		c2 = c3;
		c3 = c4;
		c4 = candle;
		if (bar1 == null || bar2 == null || bar3 == null || bar4 == null) return 0.0;
		if (bar1.close < bar1.open
			&& bar2.close < bar2.open
			&& bar3.close < bar3.open
			&& bar2.open < bar1.open
			&& bar2.close < bar1.close
			&& bar3.open < bar2.open
			&& bar3.close < bar2.close
			&& bar4.close < bar4.open
			&& bar4.high > bar4.open
			&& candle.close > candle.open
			&& candle.open > bar4.open) {
			return 1.0;
		}
		return 0.0;
	}

	public function reset():Void {
		c1 = null;
		c2 = null;
		c3 = null;
		c4 = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return hasEmitted;
	public function name():String return "LadderBottom";

	public static function spec():IndicatorSpec {
		return {
			name: "ladder_bottom", args: [], ret: TScalar, minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "ladder_bottom", Math.NaN,
				() -> new LadderBottom(), (i, b) -> (cast i : LadderBottom).update(b))
		};
	}
}
