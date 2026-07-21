package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Triple Exponential Moving Average (TEMA) — ported from wickra-core's `Tema`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/tema.rs).
 *
 * `TEMA = 3·EMA1 − 3·EMA2 + EMA3` where `EMA2 = EMA(EMA1)` and
 * `EMA3 = EMA(EMA2)`. Reduces lag further than DEMA at the cost of more
 * responsiveness to noise. Series input (f64): `tema(close, period)`.
 */
class Tema implements MuseIndicator<Float, Float> {
	var ema1:Ema;
	var ema2:Ema;
	var ema3:Ema;
	var period:Int;

	public function new(period:Int) {
		if (period <= 0) throw "Tema: period must be > 0";
		this.period = period;
		ema1 = new Ema(period);
		ema2 = new Ema(period);
		ema3 = new Ema(period);
	}

	/** Configured period. */
	public function getPeriod():Int return period;

	public function update(input:Float):Null<Float> {
		var e1 = ema1.update(input);
		if (e1 == null) return null;
		var e2 = ema2.update(e1);
		if (e2 == null) return null;
		var e3 = ema3.update(e2);
		if (e3 == null) return null;
		return 3.0 * e1 - 3.0 * e2 + e3;
	}

	public function reset():Void {
		ema1.reset();
		ema2.reset();
		ema3.reset();
	}

	public function warmupPeriod():Int return 3 * period - 2;
	public function isReady():Bool return ema3.isReady();
	public function name():String return "TEMA";

	public static function spec():IndicatorSpec {
		return {
			name: "tema", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "tema:" + series + ":" + p, series, Math.NaN,
					() -> new Tema(p), (i, v) -> (cast i : Tema).update(v));
			}
		};
	}
}
