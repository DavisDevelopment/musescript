package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * TTM Trend — ported from wickra-core's `TtmTrend`
 * (vendor/wickra/crates/wickra-core/src/indicators/ttm_trend.rs).
 *
 * John Carter's bar-coloring trend filter:
 *
 *   reference = SMA((high + low) / 2, period)
 *   TTM Trend = +1  if close > reference
 *               -1  otherwise
 *
 * The classic configuration uses the trailing six bars. Emits ±1.0 on every
 * bar after warmup. Reference: John Carter, *Mastering the Trade*, 2005.
 */
class TtmTrend implements MuseIndicator<Bar, Float> {
	var period:Int;
	var sma:Sma;

	public function new(period:Int) {
		if (period <= 0) throw "TtmTrend: period must be > 0";
		this.period = period;
		sma = new Sma(period);
	}

	public function update(candle:Bar):Null<Float> {
		var median = (candle.high + candle.low) / 2.0;
		var reference = sma.update(median);
		if (reference == null) return null;
		return candle.close > reference ? 1.0 : -1.0;
	}

	public function reset():Void {
		sma.reset();
	}

	public function warmupPeriod():Int return period;
	public function isReady():Bool return sma.isReady();
	public function name():String return "TtmTrend";

	public static function spec():IndicatorSpec {
		return {
			name: "ttm_trend", args: [TWindow], ret: TScalar, minArgs: 0,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 6);
				return IndicatorCache.evalBar(h, "ttm_trend:" + p, Math.NaN,
					() -> new TtmTrend(p), (i, b) -> (cast i : TtmTrend).update(b));
			}
		};
	}
}
