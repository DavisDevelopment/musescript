package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Sma;
import musescript.types.MuseType;

/**
 * Intraday Intensity (Bostian): a volume-weighted measure of where the
 * close settled within the bar's range, smoothed with a simple moving
 * average.
 *
 * raw_t = volume_t * (2*close_t - high_t - low_t) / (high_t - low_t)
 * II    = SMA(raw, period)
 *
 * `raw` alone is Wickra's `Adl`/`Cmf` money-flow-multiplier lineage times
 * *unnormalized* volume (no /(sum volume) division), so its magnitude
 * scales with the asset's own volume rather than being a bounded ratio.
 * Falls back to a raw value of 0 on a zero-range bar.
 */
class IntradayIntensity implements MuseIndicator<Bar, Float> {
	var sma:Sma;

	public function new(period:Int) {
		sma = new Sma(period);
	}

	public function update(bar:Bar):Null<Float> {
		var range = bar.high - bar.low;
		var raw = range == 0.0 ? 0.0 : bar.volume * (2.0 * bar.close - bar.high - bar.low) / range;
		return sma.update(raw);
	}

	public function reset():Void {
		sma.reset();
	}

	public function warmupPeriod():Int return sma.period;
	public function isReady():Bool return sma.isReady();
	public function name():String return "IntradayIntensity";

	public static function spec():IndicatorSpec {
		return {
			name: "intraday_intensity", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "intraday_intensity:" + p, Math.NaN,
					() -> new IntradayIntensity(p), (i, b) -> (cast i : IntradayIntensity).update(b));
			}
		};
	}
}
