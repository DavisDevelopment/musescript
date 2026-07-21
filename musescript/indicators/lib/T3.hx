package musescript.indicators.lib;

import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.indicators.prim.Ema;
import musescript.types.MuseType;

/**
 * Tillson's T3 Moving Average — ported from wickra-core's `T3`
 * (github.com/wickra-lib/wickra/blob/main/crates/wickra-core/src/indicators/t3.rs).
 *
 * Six chained EMAs (`e1..e6`, each of the same `period`) recombined with a
 * volume factor `v ∈ [0, 1]`:
 *
 *   c1 = −v³; c2 = 3v² + 3v³; c3 = −6v² − 3v − 3v³; c4 = 1 + 3v + v³ + 3v²
 *   T3 = c1·e6 + c2·e5 + c3·e4 + c4·e3
 *
 * `v = 0` collapses T3 to the plain triple-cascaded EMA `e3`; the
 * conventional `v = 0.7` sharpens the response to turns. First output after
 * `6·period − 5` inputs. Series input (f64): `t3(close, period, v)`.
 */
class T3 implements MuseIndicator<Float, Float> {
	var period:Int;
	var v:Float;
	public var c1(default, null):Float;
	public var c2(default, null):Float;
	public var c3(default, null):Float;
	public var c4(default, null):Float;
	var e1:Ema;
	var e2:Ema;
	var e3:Ema;
	var e4:Ema;
	var e5:Ema;
	var e6:Ema;
	var current:Null<Float>;

	public function new(period:Int, v:Float) {
		if (period <= 0) throw "T3: period must be > 0";
		if (!Math.isFinite(v) || v < 0.0 || v > 1.0) {
			throw "T3 volume factor must be a finite value in [0.0, 1.0]";
		}
		this.period = period;
		this.v = v;
		var v2 = v * v;
		var v3 = v2 * v;
		c1 = -v3;
		c2 = 3.0 * v2 + 3.0 * v3;
		c3 = -6.0 * v2 - 3.0 * v - 3.0 * v3;
		c4 = 1.0 + 3.0 * v + v3 + 3.0 * v2;
		e1 = new Ema(period);
		e2 = new Ema(period);
		e3 = new Ema(period);
		e4 = new Ema(period);
		e5 = new Ema(period);
		e6 = new Ema(period);
		current = null;
	}

	/** Configured period. */
	public function getPeriod():Int return period;

	/** Configured volume factor `v`. */
	public function volumeFactor():Float return v;

	/** Current value if available. */
	public function value():Null<Float> return current;

	public function update(input:Float):Null<Float> {
		if (!Math.isFinite(input)) {
			// Non-finite input is ignored; the cascade is not advanced.
			return current;
		}
		var o1 = e1.update(input);
		if (o1 == null) return null;
		var o2 = e2.update(o1);
		if (o2 == null) return null;
		var o3 = e3.update(o2);
		if (o3 == null) return null;
		var o4 = e4.update(o3);
		if (o4 == null) return null;
		var o5 = e5.update(o4);
		if (o5 == null) return null;
		var o6 = e6.update(o5);
		if (o6 == null) return null;
		var out = c1 * o6 + c2 * o5 + c3 * o4 + c4 * o3;
		current = out;
		return out;
	}

	public function reset():Void {
		e1.reset();
		e2.reset();
		e3.reset();
		e4.reset();
		e5.reset();
		e6.reset();
		current = null;
	}

	public function warmupPeriod():Int return 6 * period - 5;
	public function isReady():Bool return current != null;
	public function name():String return "T3";

	public static function spec():IndicatorSpec {
		return {
			name: "t3", args: [TSeries, TWindow, TScalar], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var series = IndicatorCache.seriesArg(args, 0, "close");
				var p = IndicatorCache.intArg(args, 1, 5);
				var vf = IndicatorCache.floatArg(args, 2, 0.7);
				return IndicatorCache.evalSeries(h, "t3:" + series + ":" + p + ":" + vf, series, Math.NaN,
					() -> new T3(p, vf), (i, v) -> (cast i : T3).update(v));
			}
		};
	}
}
