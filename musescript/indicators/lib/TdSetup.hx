package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.RingBuffer;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Tom DeMark TD Setup (9-bar buy / sell setup) — ported from wickra-core's
 * `TdSetup` (vendor/wickra/crates/wickra-core/src/indicators/td_setup.rs).
 *
 * Counts consecutive bars whose close is below (buy setup, positive count)
 * or above (sell setup, negative count) the close `lookback` bars earlier.
 * The magnitude caps at `target` once the setup completes; equality with the
 * reference close resets both streaks and emits 0. DeMark's classic
 * configuration is `lookback = 4`, `target = 9`.
 */
class TdSetup implements MuseIndicator<Bar, Float> {
	var lookback:Int;
	var target:Int;
	var closes:RingBuffer<Float>;
	var buyCount:Int;
	var sellCount:Int;
	var lastValue:Null<Float>;

	public function new(lookback:Int, target:Int) {
		if (lookback <= 0 || target <= 0) throw "TdSetup: lookback and target must be > 0";
		this.lookback = lookback;
		this.target = target;
		closes = new RingBuffer(lookback);
		buyCount = 0;
		sellCount = 0;
		lastValue = null;
	}

	/** DeMark's classic configuration: `lookback = 4`, `target = 9`. */
	public static function classic():TdSetup {
		return new TdSetup(4, 9);
	}

	/** Configured `[lookback, target]`. */
	public function params():Array<Int> {
		return [lookback, target];
	}

	/** Current signed setup value if available. */
	public function value():Null<Float> {
		return lastValue;
	}

	public function update(bar:Bar):Null<Float> {
		// Maintain a rolling window of the last `lookback + 1` closes so the
		// oldest entry (front) is exactly the close `lookback` bars ago.
		if (closes.length < lookback) {
			closes.push(bar.close);
			return null;
		}
		// We now have exactly `lookback` historical closes buffered; the
		// oldest is the comparison reference.
		var reference = closes.oldest(0);
		closes.push(bar.close);

		if (bar.close < reference) {
			buyCount = buyCount + 1 < target ? buyCount + 1 : target;
			sellCount = 0;
			var v:Float = buyCount;
			lastValue = v;
			return v;
		} else if (bar.close > reference) {
			sellCount = sellCount + 1 < target ? sellCount + 1 : target;
			buyCount = 0;
			var v:Float = -sellCount;
			lastValue = v;
			return v;
		} else {
			// Equality breaks both streaks; the bar emits zero.
			buyCount = 0;
			sellCount = 0;
			lastValue = 0.0;
			return 0.0;
		}
	}

	public function reset():Void {
		closes = new RingBuffer(lookback);
		buyCount = 0;
		sellCount = 0;
		lastValue = null;
	}

	public function warmupPeriod():Int return lookback + 1;
	public function isReady():Bool return lastValue != null;
	public function name():String return "TDSetup";

	public static function spec():IndicatorSpec {
		return {
			name: "td_setup", args: [TWindow, TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var lookback = IndicatorCache.intArg(args, 0, 4);
				var target = IndicatorCache.intArg(args, 1, 9);
				return IndicatorCache.evalBar(h, "td_setup:" + lookback + ":" + target, Math.NaN,
					() -> new TdSetup(lookback, target), (i, b) -> (cast i : TdSetup).update(b));
			}
		};
	}
}
