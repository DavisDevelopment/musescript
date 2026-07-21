package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Williams Fractals output for one bar. Each field is non-null when a
 * fractal high/low was confirmed at the CENTRE of the most recent five-bar
 * window (mirrors the Rust `Option<f64>` fields). Up and down fractals are
 * independent and can coincide.
 */
typedef WilliamsFractalsOutput = {
	var up:Null<Float>;
	var down:Null<Float>;
}

/**
 * Williams Fractals — ported from wickra-core's `WilliamsFractals`
 * (vendor/wickra/crates/wickra-core/src/indicators/williams_fractals.rs).
 *
 * Bill Williams' five-bar swing detector. A bar is an UP fractal if its high
 * is strictly above the highs of the two bars immediately before and the two
 * bars immediately after. A bar is a DOWN fractal if its low is strictly
 * below the lows of those same four neighbours. Because confirmation
 * requires two bars to the right of the candidate, the indicator inherently
 * lags by two bars.
 *
 * The first output lands at the fifth candle and corresponds to the third
 * candle (the centre of the window). The builtin surface encodes "no
 * fractal" as NaN.
 */
class WilliamsFractals implements MuseIndicator<Bar, WilliamsFractalsOutput> {
	// Five-bar window of {high, low} pairs. The centre is at index 2.
	var highs:Array<Float>;
	var lows:Array<Float>;

	public function new() {
		highs = [];
		lows = [];
	}

	public function update(candle:Bar):Null<WilliamsFractalsOutput> {
		if (highs.length == 5) {
			highs.shift();
			lows.shift();
		}
		highs.push(candle.high);
		lows.push(candle.low);
		if (highs.length < 5) return null;

		var h2 = highs[2];
		var l2 = lows[2];
		var up:Null<Float> = (h2 > highs[0] && h2 > highs[1] && h2 > highs[3] && h2 > highs[4]) ? h2 : null;
		var down:Null<Float> = (l2 < lows[0] && l2 < lows[1] && l2 < lows[3] && l2 < lows[4]) ? l2 : null;
		return { up: up, down: down };
	}

	public function reset():Void {
		highs = [];
		lows = [];
	}

	public function warmupPeriod():Int return 5;
	public function isReady():Bool return highs.length == 5;
	public function name():String return "WilliamsFractals";

	public static function spec():IndicatorSpec {
		return {
			name: "williams_fractals", args: [], ret: TObject([
				{name: "up", ty: TScalar}, {name: "down", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) {
				var nanFill = { up: Math.NaN, down: Math.NaN };
				return IndicatorCache.evalBar(h, "williams_fractals", nanFill,
					() -> new WilliamsFractals(), function(i, b) {
						var o = (cast i : WilliamsFractals).update(b);
						if (o == null) return null;
						// Encode the Option fields as NaN for the flat builtin.
						return {
							up: o.up == null ? Math.NaN : o.up,
							down: o.down == null ? Math.NaN : o.down
						};
					});
			}
		};
	}
}
