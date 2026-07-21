package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/** Output of `TdRangeProjection`: the projected high and low for the next bar. */
typedef TdRangeProjectionOutput = {
	var high:Float;
	var low:Float;
}

/**
 * Tom DeMark TD Range Projection — ported from wickra-core's `TdRangeProjection`
 * (vendor/wickra/crates/wickra-core/src/indicators/td_range_projection.rs).
 *
 * Next-bar high/low projection from the current bar's OHLC (DeMark's
 * "X-projection" pivot):
 *   close < open:  pivot_sum = high + 2*low + close
 *   close > open:  pivot_sum = 2*high + low + close
 *   close == open: pivot_sum = high + low + 2*close
 *   projected_high = pivot_sum / 2 - low
 *   projected_low  = pivot_sum / 2 - high
 * Stateless beyond the current bar — every input deterministically emits.
 */
class TdRangeProjection implements MuseIndicator<Bar, TdRangeProjectionOutput> {
	var lastValue:Null<TdRangeProjectionOutput>;

	public function new() {
		reset();
	}

	/** Latest projection if available. */
	public function value():Null<TdRangeProjectionOutput> return lastValue;

	public function update(bar:Bar):Null<TdRangeProjectionOutput> {
		var pivotSum = if (bar.close < bar.open) bar.high + 2.0 * bar.low + bar.close
			else if (bar.close > bar.open) 2.0 * bar.high + bar.low + bar.close
			else bar.high + bar.low + 2.0 * bar.close;
		var half = pivotSum / 2.0;
		var out = {high: half - bar.low, low: half - bar.high};
		lastValue = out;
		return out;
	}

	public function reset():Void {
		lastValue = null;
	}

	public function warmupPeriod():Int return 1;
	public function isReady():Bool return lastValue != null;
	public function name():String return "TDRangeProjection";

	public static function spec():IndicatorSpec {
		return {
			name: "td_range_projection", args: [], ret: TObject([
				{name: "high", ty: TScalar}, {name: "low", ty: TScalar}
			]), minArgs: 0,
			eval: function(h, args) return IndicatorCache.evalBar(h, "td_range_projection",
				{high: Math.NaN, low: Math.NaN},
				() -> new TdRangeProjection(), (i, b) -> (cast i : TdRangeProjection).update(b))
		};
	}
}
