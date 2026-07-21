package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Price Momentum Oscillator (DecisionPoint PMO) — ported from wickra-core's
 * `Pmo`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/pmo.rs).
 *
 * Carl Swenlin's doubly-smoothed rate of change:
 *
 *   roc_t      = (price_t / price_{t−1} − 1) · 100
 *   smoothed_t = customEMA(roc, smoothing1)_t
 *   PMO_t      = customEMA(10 · smoothed, smoothing2)_t
 *
 * `customEMA` is the DecisionPoint smoothing: smoothing constant `2 / period`
 * (not `2 / (period + 1)`), seeded from the very first value. Conventional
 * periods are `35` and `20`. Series input (f64):
 * `pmo(close, smoothing1, smoothing2)`.
 */
class Pmo implements MuseIndicator<Float, Float> {
	var smoothing1:Int;
	var smoothing2:Int;
	var prevPrice:Null<Float>;
	var ema1:CustomAlphaEma;
	var ema2:CustomAlphaEma;
	var current:Null<Float>;

	public function new(smoothing1:Int, smoothing2:Int) {
		if (smoothing1 <= 0 || smoothing2 <= 0) throw "Pmo: periods must be > 0";
		if (smoothing1 < 2 || smoothing2 < 2) throw "PMO smoothing periods must be >= 2";
		this.smoothing1 = smoothing1;
		this.smoothing2 = smoothing2;
		prevPrice = null;
		ema1 = new CustomAlphaEma(2.0 / smoothing1);
		ema2 = new CustomAlphaEma(2.0 / smoothing2);
		current = null;
	}

	/** The `(smoothing1, smoothing2)` periods. */
	public function periods():{smoothing1:Int, smoothing2:Int} {
		return {smoothing1: smoothing1, smoothing2: smoothing2};
	}

	/** Current value if available. */
	public function value():Null<Float> return current;

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input is ignored; state is left untouched.
			return current;
		}
		if (prevPrice == null) {
			prevPrice = input;
			return null;
		}
		var prev:Float = prevPrice;
		prevPrice = input;

		var roc = if (prev == 0.0) {
			// Undefined ratio against a zero price: treat momentum as flat.
			0.0;
		} else {
			(input / prev - 1.0) * 100.0;
		};
		var smoothed = ema1.update(roc);
		if (smoothed == null) return null;
		var pmo = ema2.update(10.0 * smoothed);
		if (pmo == null) return null;
		current = pmo;
		return pmo;
	}

	public function reset():Void {
		prevPrice = null;
		ema1.reset();
		ema2.reset();
		current = null;
	}

	// The first ROC needs a previous price; both customEMAs seed from their
	// first input, so the first PMO lands on the second update.
	public function warmupPeriod():Int return 2;
	public function isReady():Bool return current != null;
	public function name():String return "PMO";

	public static function spec():IndicatorSpec {
		return {
			name: "pmo", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var s1 = IndicatorCache.intArg(args, 1, 35);
				var s2 = IndicatorCache.intArg(args, 2, 20);
				return IndicatorCache.evalSeries(h, "pmo:" + series + ":" + s1 + ":" + s2, series, Math.NaN,
					() -> new Pmo(s1, s2), (i, v) -> (cast i : Pmo).update(v));
			}
		};
	}
}

/**
 * Faithful copy of wickra-core `Ema::with_alpha` behavior (ema.rs): a custom
 * smoothing factor `alpha in (0, 1]`, seeded from the very first input
 * (`warmup_period` 1). Embedded here because prim/Ema exposes only the
 * period-based SMA-seeded constructor.
 */
private class CustomAlphaEma {
	var alpha:Float;
	var oneMinusAlpha:Float;
	var current:Float;
	var seeded:Bool;

	public function new(alpha:Float) {
		if (!Math.isFinite(alpha) || alpha <= 0.0 || alpha > 1.0) {
			throw "alpha must be in (0.0, 1.0]";
		}
		this.alpha = alpha;
		oneMinusAlpha = 1.0 - alpha;
		current = 0.0;
		seeded = false;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return seeded ? current : null;
		if (seeded) {
			current = alpha * input + oneMinusAlpha * current;
			return current;
		}
		// period == 1 in Rust's with_alpha: seeds with the first input itself.
		current = input;
		seeded = true;
		return current;
	}

	public function reset():Void {
		current = 0.0;
		seeded = false;
	}
}
