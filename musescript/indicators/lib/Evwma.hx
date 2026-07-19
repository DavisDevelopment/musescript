package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Elastic Volume Weighted Moving Average: an EMA-style recursion whose decay
 * factor is driven by each bar's own volume relative to a rolling volume
 * base, so heavy-volume bars pull the average toward price faster than
 * quiet ones.
 *
 * base_t  = sum(volume, period)          (rolling `period`-bar volume total)
 * alpha_t = min(1, volume_t / base_t)
 * evwma_t = alpha_t * close_t + (1 - alpha_t) * evwma_{t-1}
 *
 * Seeded with the first bar's close.
 */
class Evwma implements MuseIndicator<Bar, Float> {
	var period:Int;
	var volWindow:Array<Float>;
	var volSum:Float;
	var current:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Evwma: period must be > 0";
		this.period = period;
		volWindow = [];
		volSum = 0.0;
		current = null;
	}

	public function update(bar:Bar):Null<Float> {
		if (volWindow.length == period) volSum -= volWindow.shift();
		volWindow.push(bar.volume);
		volSum += bar.volume;

		if (current == null) {
			current = bar.close;
			return current;
		}

		var alpha = volSum > 0.0 ? Math.min(1.0, bar.volume / volSum) : 0.0;
		current = alpha * bar.close + (1.0 - alpha) * current;
		return current;
	}

	public function reset():Void {
		volWindow = [];
		volSum = 0.0;
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return current != null;
	public function name():String return "Evwma";

	public static function spec():IndicatorSpec {
		return {
			name: "evwma", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "evwma:" + p, Math.NaN,
					() -> new Evwma(p), (i, b) -> (cast i : Evwma).update(b));
			}
		};
	}
}
