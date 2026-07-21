package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * True Strength Index — ported from wickra-core's `Tsi`
 * (vendor/wickra/crates/wickra-core/src/indicators/tsi.rs).
 *
 * William Blau's double-smoothed momentum oscillator. The 1-bar momentum
 * `price_t − price_{t−1}` and its absolute value are each smoothed twice —
 * an EMA of length `long`, then an EMA of length `short`:
 *
 * TSI = 100 · EMA_short(EMA_long(momentum)) / EMA_short(EMA_long(|momentum|))
 *
 * A roughly `[−100, 100]` oscillator centred on zero: positive means net
 * upward pressure, negative net downward. A flat double-smoothed range
 * (no momentum at all) reads `0`. Non-finite input is ignored (state left
 * untouched, current value returned). Warmup is `long + short`.
 */
class Tsi implements MuseIndicator<Float, Float> {
	var longPeriod:Int;
	var shortPeriod:Int;
	var prevPrice:Null<Float>;
	var emaLongMom:Ema;
	var emaShortMom:Ema;
	var emaLongAbs:Ema;
	var emaShortAbs:Ema;
	var current:Null<Float>;

	public function new(longPeriod:Int, shortPeriod:Int) {
		if (longPeriod == 0 || shortPeriod == 0) throw "Tsi: period must be > 0";
		this.longPeriod = longPeriod;
		this.shortPeriod = shortPeriod;
		prevPrice = null;
		emaLongMom = new Ema(longPeriod);
		emaShortMom = new Ema(shortPeriod);
		emaLongAbs = new Ema(longPeriod);
		emaShortAbs = new Ema(shortPeriod);
		current = null;
	}

	/** Current value if available (null before warmup). */
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

		var momentum = input - prev;
		var lm = emaLongMom.update(momentum);
		var dsMom = lm == null ? null : emaShortMom.update(lm);
		var la = emaLongAbs.update(Math.abs(momentum));
		var dsAbs = la == null ? null : emaShortAbs.update(la);

		if (dsMom == null || dsAbs == null) return null;
		// Flat double-smoothed range: there is no momentum at all.
		var tsi = dsAbs == 0.0 ? 0.0 : 100.0 * dsMom / dsAbs;
		current = tsi;
		return tsi;
	}

	public function reset():Void {
		prevPrice = null;
		emaLongMom.reset();
		emaShortMom.reset();
		emaLongAbs.reset();
		emaShortAbs.reset();
		current = null;
	}

	public function warmupPeriod():Int return longPeriod + shortPeriod;
	public function isReady():Bool return current != null;
	public function name():String return "TSI";

	public static function spec():IndicatorSpec {
		return {
			name: "tsi", args: [TSeries, TWindow, TWindow], ret: TScalar, minArgs: 2,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var lp = IndicatorCache.intArg(args, 1, 25);
				var sp = IndicatorCache.intArg(args, 2, 13);
				var key = "tsi:" + series + ":" + lp + ":" + sp;
				return IndicatorCache.evalSeries(h, key, series, Math.NaN,
					() -> new Tsi(lp, sp), (i, v) -> (cast i : Tsi).update(v));
			}
		};
	}
}
