package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Generalized DEMA: DEMA with a tunable "volume factor" `v` controlling how
 * aggressively lag is extrapolated away. `v = 1` reproduces the classic
 * DEMA exactly; `v = 0` reduces to a plain EMA (no extrapolation); larger
 * `v` extrapolates more aggressively (less lag, more overshoot risk).
 *
 * GDEMA = (1 + v) * EMA(price, period) - v * EMA(EMA(price, period), period)
 */
class GeneralizedDema implements MuseIndicator<Float, Float> {
	var ema1:Ema;
	var ema2:Ema;
	var v:Float;

	public function new(period:Int, v:Float) {
		if (!Math.isFinite(v) || v < 0.0) throw "GeneralizedDema: v must be >= 0 and finite";
		ema1 = new Ema(period);
		ema2 = new Ema(period);
		this.v = v;
	}

	public function update(price:Float):Null<Float> {
		var e1 = ema1.update(price);
		if (e1 == null) return null;
		var e2 = ema2.update(e1);
		if (e2 == null) return null;
		return (1.0 + v) * e1 - v * e2;
	}

	public function reset():Void {
		ema1.reset();
		ema2.reset();
	}

	public function warmupPeriod():Int return ema1.period * 2 - 1;
	public function isReady():Bool return ema2.isReady();
	public function name():String return "GeneralizedDema";

	public static function spec():IndicatorSpec {
		return {
			name: "generalized_dema", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				var v = IndicatorCache.floatArg(args, 2, 1.0);
				return IndicatorCache.evalSeries(h, "generalized_dema:" + series + ":" + p + ":" + v, series, Math.NaN,
					() -> new GeneralizedDema(p, v), (i, x) -> (cast i : GeneralizedDema).update(x));
			}
		};
	}
}
