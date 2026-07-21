package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Zero-Lag Exponential Moving Average (Ehlers & Way) — ported from
 * wickra-core's `Zlema`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/zlema.rs).
 *
 * A standard EMA applied to a de-lagged price series
 * `2·price_t − price_{t−lag}` with `lag = (period − 1) / 2`; the momentum
 * term cancels most of the EMA's group delay. First output after exactly
 * `lag + period` inputs. Series input (f64): `zlema(close, period)`.
 */
class Zlema implements MuseIndicator<Float, Float> {
	var period:Int;
	var lag:Int;
	/** Rolling buffer of the last `lag + 1` raw inputs, oldest at the front. */
	var window:Array<Float>;
	var ema:Ema;

	public function new(period:Int) {
		if (period <= 0) throw "Zlema: period must be > 0";
		this.period = period;
		this.lag = Std.int((period - 1) / 2);
		window = [];
		ema = new Ema(period);
	}

	/** Configured period. */
	public function getPeriod():Int return period;

	/** Lag offset `(period − 1) / 2` used to de-lag the price series. */
	public function getLag():Int return lag;

	/** Current value if available. */
	public function value():Null<Float> {
		return ema.isReady() ? ema.value() : null;
	}

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input is ignored; state is left untouched.
			return value();
		}
		if (window.length == lag + 1) window.shift();
		window.push(input);
		if (window.length < lag + 1) return null;
		var lagged = window[0];
		var deLagged = 2.0 * input - lagged;
		return ema.update(deLagged);
	}

	public function reset():Void {
		window = [];
		ema.reset();
	}

	public function warmupPeriod():Int return lag + period;
	public function isReady():Bool return ema.isReady();
	public function name():String return "ZLEMA";

	public static function spec():IndicatorSpec {
		return {
			name: "zlema", args: [TSeries, TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 14);
				return IndicatorCache.evalSeries(h, "zlema:" + series + ":" + p, series, Math.NaN,
					() -> new Zlema(p), (i, v) -> (cast i : Zlema).update(v));
			}
		};
	}
}
