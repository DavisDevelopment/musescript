package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * TRIX — ported from wickra-core's `Trix`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/trix.rs).
 *
 * The 1-period percent rate of change of a triple-smoothed EMA:
 * `TRIX = 100 · (TR_t − TR_{t−1}) / TR_{t−1}` where
 * `TR_t = EMA(EMA(EMA(price)))`. A zero previous triple-EMA emits `0.0`
 * rather than dividing by zero. Series input (f64): `trix(close, period)`.
 */
class Trix implements MuseIndicator<Float, Float> {
	var ema1:Ema;
	var ema2:Ema;
	var ema3:Ema;
	var prevTr:Null<Float>;
	var period:Int;

	public function new(period:Int) {
		if (period <= 0) throw "Trix: period must be > 0";
		this.period = period;
		ema1 = new Ema(period);
		ema2 = new Ema(period);
		ema3 = new Ema(period);
		prevTr = null;
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
		if (prevTr == null) {
			prevTr = e3;
			return null;
		}
		var prev:Float = prevTr;
		prevTr = e3;
		if (prev != 0.0) {
			return 100.0 * (e3 - prev) / prev;
		}
		return 0.0;
	}

	public function reset():Void {
		ema1.reset();
		ema2.reset();
		ema3.reset();
		prevTr = null;
	}

	// Triple EMA seeds at 3*period-2; plus one extra for the rate of change.
	public function warmupPeriod():Int return 3 * period - 1;
	public function isReady():Bool return prevTr != null && ema3.isReady();
	public function name():String return "TRIX";

	public static function spec():IndicatorSpec {
		return {
			name: "trix", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 30);
				return IndicatorCache.evalSeries(h, "trix:" + series + ":" + p, series, Math.NaN,
					() -> new Trix(p), (i, v) -> (cast i : Trix).update(v));
			}
		};
	}
}
