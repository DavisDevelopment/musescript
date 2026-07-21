package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Volume-Weighted Moving Average — ported from wickra-core's `Vwma`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/vwma.rs).
 *
 *   VWMA_t = sum(close_i * volume_i) / sum(volume_i)   over the last `period` bars
 *
 * If every candle in the window has zero volume the weighted mean is
 * undefined; the indicator then falls back to the unweighted mean of the
 * `period` closes, so the output is always finite.
 */
class Vwma implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var closes:Array<Float>;
	var volumes:Array<Float>;
	var sumPv:Float;
	var sumV:Float;
	var sumClose:Float;
	var current:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Vwma: period must be > 0";
		this.period = period;
		reset();
	}

	/** Current value if available (null during warmup). */
	public function value():Null<Float> return current;

	public function update(bar:Bar):Null<Float> {
		var close = bar.close;
		var volume = bar.volume;
		if (closes.length == period) {
			var oldClose = closes.shift();
			var oldVolume = volumes.shift();
			sumPv -= oldClose * oldVolume;
			sumV -= oldVolume;
			sumClose -= oldClose;
		}
		closes.push(close);
		volumes.push(volume);
		sumPv += close * volume;
		sumV += volume;
		sumClose += close;
		if (closes.length < period) return null;
		var value = if (sumV > 0.0) {
			sumPv / sumV;
		} else {
			// Degenerate window: every bar had zero volume. Fall back to the
			// plain mean of the closes so the output stays finite.
			sumClose / period;
		};
		current = value;
		return value;
	}

	public function reset():Void {
		closes = [];
		volumes = [];
		sumPv = 0.0;
		sumV = 0.0;
		sumClose = 0.0;
		current = null;
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return current != null;
	public function name():String return "VWMA";

	public static function spec():IndicatorSpec {
		return {
			name: "vwma", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 20);
				return IndicatorCache.evalBar(h, "vwma:" + p, Math.NaN,
					() -> new Vwma(p), (i, b) -> (cast i : Vwma).update(b));
			}
		};
	}
}
