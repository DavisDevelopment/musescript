package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Wilder's Average Directional Movement Index Rating (ADXR) — ported from
 * wickra-core's `Adxr`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/adxr.rs).
 *
 * Smooths the `Adx` line by averaging its current value with the value it had
 * `period` bars ago: `ADXR_t = (ADX_t + ADX_{t - (period - 1)}) / 2`. The
 * first complete `ADXR` is emitted after `3 * period - 1` candles.
 */
class Adxr implements MuseIndicator<Bar, Float> {
	var period:Int;
	var adx:Adx;
	var window:Array<Float>;
	var last:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Adxr: period must be > 0";
		this.period = period;
		this.adx = new Adx(period);
		this.window = [];
		this.last = null;
	}

	public function update(candle:Bar):Null<Float> {
		var adxOut = adx.update(candle);
		if (adxOut == null) return null;
		var adxValue = adxOut.adx;

		if (window.length == period) {
			window.shift();
		}
		window.push(adxValue);
		if (window.length < period) return null;

		var oldest = window[0];
		var adxr = (adxValue + oldest) / 2.0;
		last = adxr;
		return adxr;
	}

	public function reset():Void {
		adx.reset();
		window = [];
		last = null;
	}

	public function warmupPeriod():Int return 3 * period - 1;
	public function isReady():Bool return last != null;
	public function name():String return "ADXR";

	public static function spec():IndicatorSpec {
		return {
			name: "adxr", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "adxr:" + p, Math.NaN,
					() -> new Adxr(p), (i, b) -> (cast i : Adxr).update(b));
			}
		};
	}
}
