package musescript.indicators.lib;

import musescript.harness.Bar;
import musescript.indicators.MuseIndicator;
import musescript.indicators.IndicatorSpec;
import musescript.indicators.IndicatorCache;
import musescript.types.MuseType;

/**
 * Directional Movement Index (DX): the raw, un-smoothed directional
 * imbalance that `Adx` averages over time to produce the ADX line itself.
 * Exposed standalone since some strategies read DX directly rather than its
 * smoothed form.
 *
 * Same Wilder-smoothed +DI / -DI machinery as `Adx` (see that file), but DX
 * is emitted every bar once the DI seed is warm, with no additional
 * period-length averaging on top:
 *
 * DX = 100 * |+DI - -DI| / (+DI + -DI)
 */
class Dx implements MuseIndicator<Bar, Float> {
	var period:Int;
	var prev:Null<Bar>;
	var trSeed:Float;
	var plusDmSeed:Float;
	var minusDmSeed:Float;
	var seedCount:Int;
	var trSmooth:Null<Float>;
	var plusDmSmooth:Null<Float>;
	var minusDmSmooth:Null<Float>;

	public function new(period:Int) {
		if (period <= 0) throw "Dx: period must be > 0";
		this.period = period;
		reset();
	}

	public function update(candle:Bar):Null<Float> {
		if (prev == null) {
			prev = candle;
			return null;
		}

		var tr = trueRange(prev, candle);
		var dm = directionalMovement(prev, candle);
		var n:Float = period;

		var trV:Float;
		var plusV:Float;
		var minusV:Float;

		if (trSmooth != null && plusDmSmooth != null && minusDmSmooth != null) {
			trV = trSmooth - trSmooth / n + tr;
			plusV = plusDmSmooth - plusDmSmooth / n + dm.plusDm;
			minusV = minusDmSmooth - minusDmSmooth / n + dm.minusDm;
			trSmooth = trV;
			plusDmSmooth = plusV;
			minusDmSmooth = minusV;
		} else {
			trSeed += tr;
			plusDmSeed += dm.plusDm;
			minusDmSeed += dm.minusDm;
			seedCount++;
			prev = candle;
			if (seedCount < period) return null;
			trSmooth = trSeed;
			plusDmSmooth = plusDmSeed;
			minusDmSmooth = minusDmSeed;
			trV = trSeed;
			plusV = plusDmSeed;
			minusV = minusDmSeed;
		}
		prev = candle;

		var plusDi = trV == 0.0 ? 0.0 : 100.0 * plusV / trV;
		var minusDi = trV == 0.0 ? 0.0 : 100.0 * minusV / trV;
		var dxDen = plusDi + minusDi;
		return dxDen == 0.0 ? 0.0 : 100.0 * Math.abs(plusDi - minusDi) / dxDen;
	}

	public function reset():Void {
		prev = null;
		trSeed = 0.0;
		plusDmSeed = 0.0;
		minusDmSeed = 0.0;
		seedCount = 0;
		trSmooth = null;
		plusDmSmooth = null;
		minusDmSmooth = null;
	}

	public function warmupPeriod():Int return period + 1;
	public function isReady():Bool return trSmooth != null;
	public function name():String return "DX";

	static function trueRange(prev:Bar, current:Bar):Float {
		var hl = current.high - current.low;
		var hc = Math.abs(current.high - prev.close);
		var lc = Math.abs(current.low - prev.close);
		return Math.max(hl, Math.max(hc, lc));
	}

	static function directionalMovement(prev:Bar, current:Bar):{plusDm:Float, minusDm:Float} {
		var up = current.high - prev.high;
		var down = prev.low - current.low;
		var plusDm = (up > down && up > 0.0) ? up : 0.0;
		var minusDm = (down > up && down > 0.0) ? down : 0.0;
		return { plusDm: plusDm, minusDm: minusDm };
	}

	public static function spec():IndicatorSpec {
		return {
			name: "dx", args: [TWindow], ret: TScalar, minArgs: 1,
			eval: function(h, args) {
				var p = IndicatorCache.intArg(args, 0, 14);
				return IndicatorCache.evalBar(h, "dx:" + p, Math.NaN,
					() -> new Dx(p), (i, b) -> (cast i : Dx).update(b));
			}
		};
	}
}
