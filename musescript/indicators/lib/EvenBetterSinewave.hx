package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.SuperSmoother;
import musescript.harness.HarnessContext;
import musescript.types.MuseType;

/**
 * Ehlers Even Better Sinewave (EBSW) — ported from wickra-core's `EvenBetterSinewave`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/even_better_sinewave.rs).
 *
 * A self-normalising cycle oscillator that swings in [-1, +1]. Applies a highpass
 * filter followed by SuperSmoother, then divides a 3-bar average by the RMS power
 * to self-normalise the amplitude. The result reads like a clean sine wave regardless
 * of price amplitude.
 *
 * From John Ehlers' *Cycle Analytics for Traders* (2013, ch. 12).
 */
class EvenBetterSinewave implements MuseIndicator<Float, Float> {
	var hpPeriod:Int;
	var ssfLength:Int;
	var alpha1:Float;
	var smoother:SuperSmoother;
	var prevPrice:Null<Float>;
	var hp:Float;
	var filt1:Null<Float>;
	var filt2:Null<Float>;
	var filt3:Null<Float>;
	var last:Null<Float>;

	public function new(hpPeriod:Int, ssfLength:Int) {
		if (hpPeriod <= 0 || ssfLength <= 0) throw "EvenBetterSinewave: periods must be > 0";
		this.hpPeriod = hpPeriod;
		this.ssfLength = ssfLength;

		var w = 2.0 * Math.PI / hpPeriod;
		this.alpha1 = (1.0 - Math.sin(w)) / Math.cos(w);
		this.smoother = new SuperSmoother(ssfLength);
		this.prevPrice = null;
		this.hp = 0.0;
		this.filt1 = null;
		this.filt2 = null;
		this.filt3 = null;
		this.last = null;
	}

	public function update(price:Float):Null<Float> {
		if (!Math.isFinite(price)) return last;

		var hp:Float = if (prevPrice != null) {
			0.5 * (1.0 + alpha1) * (price - prevPrice) + alpha1 * this.hp;
		} else {
			0.0;
		};
		prevPrice = price;
		this.hp = hp;

		var filt = smoother.update(hp);
		if (filt == null) return null;

		// Shift the three-deep filter buffer.
		filt3 = filt2;
		filt2 = filt1;
		filt1 = filt;

		if (filt1 == null || filt2 == null || filt3 == null) return null;

		var f1 = filt1, f2 = filt2, f3 = filt3;
		var wave = (f1 + f2 + f3) / 3.0;
		var pwr = (f1 * f1 + f2 * f2 + f3 * f3) / 3.0;
		var ebsw = if (pwr > 0.0) {
			var raw = wave / Math.sqrt(pwr);
			// Clamp to [-1, 1]
			if (raw < -1.0) -1.0 else if (raw > 1.0) 1.0 else raw;
		} else {
			0.0;
		};

		last = ebsw;
		return ebsw;
	}

	public function reset():Void {
		smoother.reset();
		prevPrice = null;
		hp = 0.0;
		filt1 = null;
		filt2 = null;
		filt3 = null;
		last = null;
	}

	public function warmupPeriod():Int return 3;
	public function isReady():Bool return last != null;
	public function name():String return "EvenBetterSinewave";

	public static function spec():IndicatorSpec {
		return {
			name: "even_better_sinewave", args: [TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var hp = IndicatorCache.intArg(args, 0, 40);
				var ssf = IndicatorCache.intArg(args, 1, 10);
				return IndicatorCache.evalSeries(h, "even_better_sinewave:" + hp + ":" + ssf, "close", Math.NaN,
					() -> new EvenBetterSinewave(hp, ssf),
					(i, p) -> (cast i : EvenBetterSinewave).update(p));
			}
		};
	}
}
