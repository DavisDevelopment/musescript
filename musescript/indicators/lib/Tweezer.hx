package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tweezer Top / Bottom candlestick pattern — ported from wickra-core's
 * `Tweezer` (vendor/wickra/crates/wickra-core/src/indicators/tweezer.rs).
 *
 * A 2-bar reversal pattern where two consecutive candles share an extreme:
 *
 *   tol_high     = tolerance * max(|prev.high|, |curr.high|)
 *   tol_low      = tolerance * max(|prev.low|,  |curr.low|)
 *   tweezer_top  = |curr.high − prev.high| <= tol_high
 *   tweezer_bot  = |curr.low  − prev.low|  <= tol_low
 *
 * Output is −1.0 for a Tweezer Top (matched highs), +1.0 for a Tweezer
 * Bottom (matched lows), and 0.0 otherwise. If BOTH extremes match, the
 * bottom wins by convention (bullish rejection of the low). `tolerance`
 * defaults to 0.001 and must lie in [0, 1). The first bar returns 0.0.
 */
class Tweezer implements MuseIndicator<Bar, Float> {
	var toleranceValue:Float;
	var prev:Null<Bar>;
	var hasEmitted:Bool;

	public function new(tolerance:Float = 0.001) {
		if (!(tolerance >= 0.0 && tolerance < 1.0))
			throw "Tweezer: tolerance must be in [0, 1)";
		this.toleranceValue = tolerance;
		prev = null;
		hasEmitted = false;
	}

	/** Configured relative tolerance. */
	public function tolerance():Float return toleranceValue;

	public function update(candle:Bar):Null<Float> {
		hasEmitted = true;
		var p = prev;
		prev = candle;
		if (p == null) return 0.0;
		var tolHigh = toleranceValue * Math.max(Math.abs(p.high), Math.abs(candle.high));
		var tolLow = toleranceValue * Math.max(Math.abs(p.low), Math.abs(candle.low));
		var matchLow = Math.abs(candle.low - p.low) <= tolLow;
		var matchHigh = Math.abs(candle.high - p.high) <= tolHigh;
		if (matchLow) return 1.0;
		if (matchHigh) return -1.0;
		return 0.0;
	}

	public function reset():Void {
		prev = null;
		hasEmitted = false;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return hasEmitted;
	public function name():String return "Tweezer";

	public static function spec():IndicatorSpec {
		return {
			name: "tweezer", args: [TScalar], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var tol = IndicatorCache.floatArg(args, 0, 0.001);
				return IndicatorCache.evalBar(h, "tweezer:" + tol, Math.NaN,
					() -> new Tweezer(tol), (i, b) -> (cast i : Tweezer).update(b));
			}
		};
	}
}
