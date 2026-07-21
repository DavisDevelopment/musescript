package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Variable Index Dynamic Average (VIDYA) — ported from wickra-core's `Vidya`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/vidya.rs).
 *
 * Tushar Chande's EMA whose smoothing factor is scaled by the absolute
 * Chande Momentum Oscillator:
 *
 *   alpha_base = 2 / (period + 1)
 *   alpha_t    = alpha_base · |CMO(cmo_period)| / 100
 *   VIDYA_t    = alpha_t · price_t + (1 − alpha_t) · VIDYA_{t−1}
 *
 * Seeded with the first price emitted after the CMO warm-up (i.e. after
 * `cmo_period + 1` inputs). Reference: Tushar Chande, *Stocks & Commodities*,
 * 1992. Series input (f64): `vidya(close, period, cmo_period)`.
 */
class Vidya implements MuseIndicator<Float, Float> {
	var period:Int;
	var cmoPeriod:Int;
	var alphaBase:Float;
	var cmo:Cmo;
	var current:Null<Float>;

	public function new(period:Int, cmoPeriod:Int) {
		if (period <= 0 || cmoPeriod <= 0) throw "Vidya: periods must be > 0";
		this.period = period;
		this.cmoPeriod = cmoPeriod;
		alphaBase = 2.0 / (period + 1.0);
		cmo = new Cmo(cmoPeriod);
		current = null;
	}

	/** Configured `(period, cmo_period)`. */
	public function periods():{period:Int, cmo_period:Int} {
		return {period: period, cmo_period: cmoPeriod};
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) return current;
		var cmoVal = cmo.update(input);
		if (cmoVal == null) return null;
		var alpha = alphaBase * (Math.abs(cmoVal) / 100.0);
		var prev:Float = current != null ? current : input;
		var next = alpha * input + (1.0 - alpha) * prev;
		current = next;
		return next;
	}

	public function reset():Void {
		cmo.reset();
		current = null;
	}

	public function warmupPeriod():Int return cmoPeriod + 1;
	public function isReady():Bool return current != null;
	public function name():String return "VIDYA";

	public static function spec():IndicatorSpec {
		return {
			name: "vidya", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				var cp = IndicatorCache.intArg(args, 2, 9);
				return IndicatorCache.evalSeries(h, "vidya:" + series + ":" + p + ":" + cp, series, Math.NaN,
					() -> new Vidya(p, cp), (i, v) -> (cast i : Vidya).update(v));
			}
		};
	}
}
