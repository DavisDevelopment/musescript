package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * New Price Lines — ported from wickra-core's `NewPriceLines`
 * (vendor/wickra/crates/wickra-core/src/indicators/new_price_lines.rs).
 *
 * The Japanese "shinne" (new-price) exhaustion count: when the close has made
 * `count` consecutive new highs (or lows), the trend is considered stretched.
 *
 *   signal = −1 once `count` consecutive higher closes (overbought / sell warning)
 *   signal = +1 once `count` consecutive lower  closes (oversold / buy warning)
 *   signal =  0 otherwise
 *
 * The signal stays active for every bar the streak remains at or above
 * `count`, and clears the moment a close breaks the streak. First value on
 * the second bar; each update is O(1).
 */
class NewPriceLines implements MuseIndicator<Bar, Float> {
	var count:Int;
	var prevClose:Null<Float>;
	var consecUp:Int;
	var consecDown:Int;
	var last:Null<Float>;

	public function new(count:Int) {
		if (count < 2) throw "NewPriceLines: new price lines count must be >= 2";
		this.count = count;
		reset();
	}

	public function update(candle:Bar):Null<Float> {
		var close = candle.close;
		if (prevClose == null) {
			prevClose = close;
			return null;
		}
		var prev:Float = prevClose;
		if (close > prev) {
			consecUp++;
			consecDown = 0;
		} else if (close < prev) {
			consecDown++;
			consecUp = 0;
		} else {
			consecUp = 0;
			consecDown = 0;
		}
		prevClose = close;

		var v = if (consecUp >= count) -1.0 else if (consecDown >= count) 1.0 else 0.0;
		last = v;
		return v;
	}

	public function reset():Void {
		prevClose = null;
		consecUp = 0;
		consecDown = 0;
		last = null;
	}

	public function warmupPeriod():Int return 2;
	public function isReady():Bool return last != null;
	public function name():String return "NewPriceLines";

	/** Current consecutive streak `{up, down}` — mirrors the Rust accessor. */
	public function streak():{up:Int, down:Int} return {up: consecUp, down: consecDown};

	public static function spec():IndicatorSpec {
		return {
			name: "new_price_lines", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var c = IndicatorCache.intArg(args, 0, 8);
				return IndicatorCache.evalBar(h, "new_price_lines:" + c, Math.NaN,
					() -> new NewPriceLines(c), (i, b) -> (cast i : NewPriceLines).update(b));
			}
		};
	}
}
