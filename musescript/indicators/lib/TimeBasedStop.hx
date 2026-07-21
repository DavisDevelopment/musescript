package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Time-Based Stop — ported from wickra-core's `TimeBasedStop`
 * (vendor/wickra/crates/wickra-core/src/indicators/time_based_stop.rs).
 *
 * Exits a position purely on elapsed bars, independent of price:
 *
 *   barsHeld increments by 1 each bar (since the last reset)
 *   progress = min(barsHeld / maxBars, 1.0)   in [0, 1]
 *   the stop fires when progress reaches 1.0 (barsHeld >= maxBars)
 *
 * A pure timer — it ignores the candle's prices entirely. Call `reset()` on
 * each new entry so the timer restarts from the position open. The first bar
 * already emits a value (1 / maxBars).
 */
class TimeBasedStop implements MuseIndicator<Bar, Float> {
	var maxBars:Int;
	var barsHeld:Int;
	var last:Null<Float>;

	public function new(maxBars:Int) {
		if (maxBars <= 0) throw "TimeBasedStop: max_bars must be > 0";
		this.maxBars = maxBars;
		barsHeld = 0;
		last = null;
	}

	/** Number of bars held since the last reset. */
	public function heldBars():Int return barsHeld;

	/** Whether the stop has fired (the holding period has fully elapsed). */
	public function triggered():Bool return barsHeld >= maxBars;

	public function update(bar:Bar):Null<Float> {
		barsHeld += 1;
		var progress = Math.min(barsHeld / maxBars, 1.0);
		last = progress;
		return progress;
	}

	public function reset():Void {
		barsHeld = 0;
		last = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return last != null;
	public function name():String return "TimeBasedStop";

	public static function spec():IndicatorSpec {
		return {
			name: "time_based_stop", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var m = IndicatorCache.intArg(args, 0, 5);
				var key = "time_based_stop:" + m;
				return IndicatorCache.evalBar(h, key, Math.NaN,
					() -> new TimeBasedStop(m), (i, b) -> (cast i : TimeBasedStop).update(b));
			}
		};
	}
}
