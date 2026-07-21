package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Volume Zone Oscillator (Walid Khalil) — ported from wickra-core's `Vzo`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/vzo.rs).
 *
 *   R_t   = sign(close_t - close_{t-1}) * volume_t
 *   VP_t  = EMA(R, period)
 *   TV_t  = EMA(volume, period)
 *   VZO_t = 100 * VP_t / TV_t
 *
 * Bounded in [-100, 100]. The first bar only seeds the previous close; both
 * EMAs then need `period` samples, so the first emission lands at bar
 * `period + 1`. A TV of 0 collapses the output to 0 instead of NaN.
 */
class Vzo implements MuseIndicator<Bar, Float> {
	public var period(default, null):Int;
	var vp:Ema;
	var tv:Ema;
	var prevClose:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Vzo: period must be > 0";
		this.period = period;
		vp = new Ema(period);
		tv = new Ema(period);
		prevClose = null;
	}

	public function update(bar:Bar):Null<Float> {
		if (prevClose == null) {
			prevClose = bar.close;
			return null;
		}
		var signedVolume = if (bar.close > prevClose) {
			bar.volume;
		} else if (bar.close < prevClose) {
			-bar.volume;
		} else {
			0.0;
		};
		prevClose = bar.close;
		var vpV = vp.update(signedVolume);
		var tvV = tv.update(bar.volume);
		if (vpV == null || tvV == null) return null;
		if (tvV == 0.0) {
			// No volume in the smoothing window -> ratio undefined; report 0.
			return 0.0;
		}
		return 100.0 * vpV / tvV;
	}

	public function reset():Void {
		vp.reset();
		tv.reset();
		prevClose = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return vp.isReady() && tv.isReady();
	public function name():String return "VZO";

	public static function spec():IndicatorSpec {
		return {
			name: "vzo", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "vzo:" + p, Math.NaN,
					() -> new Vzo(p), (i, b) -> (cast i : Vzo).update(b));
			}
		};
	}
}
